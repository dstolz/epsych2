/*
  Arduino Nano (ATmega328P) controller for:
    - NEMA 11 stepper motor (11HS18-0674S)
    - DM320T digital stepper driver (STEP/DIR/ENA)

  FEATURES
    1) Serial (USB) ASCII protocol for commands + status queries
    2) USB control of direction (CW/CCW) and speed
    3) Joystick (1 analog axis) control of direction + speed
    4) USB command to enable/disable stepper driver
    5) USB polling of commanded step position
    6) Programmable rotational speed limit (RPM)
    7) Relative move command: rotate by degrees CW (+) / CCW (-)
    8) Onboard LED (LED_BUILTIN) illuminates during motion

  ----------------------
  WIRING (DM320T P1)
  ----------------------
  DM320T control connector (P1) pins: OPTO, DIR, PUL, ENA

  Recommended simple wiring using the DM320T manual's single-ended/open-collector style:
    - Nano +5V  -> DM320T OPTO
    - Nano D2   -> DM320T PUL   (STEP)
    - Nano D3   -> DM320T DIR
    - Nano D4   -> DM320T ENA   (Enable)

  Notes:
    - DM320T inputs are opto-isolated. With the above wiring, you typically do NOT need to tie Nano GND to
      the DM320T power GND for the control signals.
    - Configure DM320T microstep + current with its DIP switches.

  Joystick (one axis):
    - Joystick VCC -> Nano +5V
    - Joystick GND -> Nano GND
    - Joystick VRx (or VRy) -> Nano A0

  ----------------------
  SERIAL PROTOCOL
  ----------------------
  - 115200 baud, newline-terminated ASCII commands.
  - Tokens separated by spaces.
  - Replies are one line per response.

  Core commands:
    HELP
      Print command help and descriptions.

    EN <0|1>   (and EN?)
      Enable/disable the DM320T driver via ENA.

    MODE <USB|JOY|AUTO>   (and MODE?)
      USB  : continuous speed/dir comes from serial setpoint
      JOY  : continuous speed/dir comes from joystick
      AUTO : joystick overrides when deflected beyond deadband; otherwise serial

    DIR <CW|CCW>   (and DIR?)
      Set serial direction for continuous motion.

    SPD <steps_per_second>   (and SPD?)
      Set continuous speed in steps/s (microsteps/s). Negative values flip DIR.

    RPM <rpm>   (and RPM?)
      Set continuous speed in RPM. Negative values flip DIR.

    LIMRPM <rpm>   (and LIMRPM?)
      Set maximum allowed RPM (applies to USB, joystick scaling, and MOVEDEG).

    STOP
      Stop continuous motion and cancel any active MOVE.

    POS?
      Query commanded position in microsteps.

    POSD?
      Query commanded position in degrees (open-loop).

    ZERO
      Set commanded position counter to 0.

    STATUS?
      One-line status dump.

    ENDELAY <ms>   (and ENDELAY?)
      Delay between asserting ENA and the first step pulse.

    GEAR <driver_teeth> <driven_teeth> [outdir]   (and GEAR?)
      Motor-to-output gearing; outdir is +1 or -1.

    SERQUIET <0|1>   (and SERQUIET?)
      When 1, POS?/POSD?/STATUS?/MOVE?/GEAR?/HELP answer "BUSY" while the motor
      is moving, so telemetry cannot disturb step timing. Default 0: a polling
      host (peripherals.NanoMotorControl) expects a value, not "BUSY".

  Relative motion:
    MOVEDEG <deg> [rpm]
      Rotate relative to current position by <deg> degrees.
      Positive deg = CW. Negative deg = CCW.
      Optional [rpm] sets move speed magnitude; otherwise uses current USB RPM if set,
      else DEFAULT_MOVE_RPM.

    MOVE?
      Query move state (active flag, target, remaining, remaining degrees, move RPM).

    CANCEL
      Cancel an in-progress MOVE.

  Notes on position:
    - Position is open-loop (commanded steps). If steps are missed mechanically, POS/POSD will not reflect that.

  ----------------------
  HOST
  ----------------------
  The MATLAB side of this protocol is peripherals.NanoMotorControl (and its GUI,
  peripherals.NanoMotorControlGUI), which sends one command and reads one line back.
  Two rules follow from that and are easy to break:
    - Every reply is exactly one line, and floats are rendered with dtostrf. The
      Arduino AVR core links avr-libc's integer-only vfprintf, so a "%f" in an
      snprintf format emits '?' and the host's parse fails.
    - Replies must not be dropped or reordered; see txBegin/txCommit/txFlush.
*/

#include <Arduino.h>
#include <ctype.h>
#include <string.h>
#include <stdlib.h>
#include <stdarg.h>
#include <math.h>
#include <avr/pgmspace.h>

// ----------------------
// DEBUG / SERIAL PLOTTER
// ----------------------
// Set SERIAL_PLOTTER_DEBUG to 1 (compile-time) to enable Serial Plotter streaming.
// NOTE: Streaming serial data can reduce maximum achievable step rate (use for debugging / lower speeds).
#ifndef SERIAL_PLOTTER_DEBUG
#define SERIAL_PLOTTER_DEBUG 0
#endif

#if SERIAL_PLOTTER_DEBUG
static const uint16_t PLOT_PERIOD_MS = 50; // plot update period
static uint32_t nextPlotMs = 0;
#endif

// ----------------------
// PIN CONFIG
// ----------------------
static const uint8_t PIN_STEP = 2;          // Nano D2 -> DM320T PUL
static const uint8_t PIN_DIR  = 3;          // Nano D3 -> DM320T DIR
static const uint8_t PIN_ENA  = 4;          // Nano D4 -> DM320T ENA
static const uint8_t PIN_JOY  = A0;         // Joystick axis
static const uint8_t PIN_TTL_EN = 5;        // TTL output mirror of driver enable (D5)
static const uint8_t PIN_LED  = LED_BUILTIN; // Onboard LED (Nano: D13)

// Fast I/O on ATmega328P (Nano): D2=PD2, D3=PD3, D4=PD4.
// Using direct port writes keeps pulse generation reliable at higher step rates.
#define STEP_BIT 2
#define DIR_BIT  3
#define ENA_BIT  4
// D5 is PD5 on ATmega328P (TTL enable mirror)
#define TTL_EN_BIT 5

// Define which DIR logic corresponds to CW.
// If your motor spins opposite to expectation, flip these levels OR swap one coil (A+ <-> A-).
static const uint8_t DIR_CW_LEVEL  = HIGH;
static const uint8_t DIR_CCW_LEVEL = LOW;

// DM320T enable logic in the typical single-ended wiring:
//   ENA HIGH -> enabled, ENA LOW -> disabled. (Default if ENA left unconnected: enabled.)
static const uint8_t ENA_ENABLE_LEVEL  = HIGH;
static const uint8_t ENA_DISABLE_LEVEL = LOW;

// STEP output convention used here: keep HIGH, generate LOW pulse then return HIGH.
static const uint8_t STEP_IDLE_LEVEL   = HIGH;
static const uint8_t STEP_ACTIVE_LEVEL = LOW;

// ----------------------
// MOTION CONFIG
// ----------------------
static const uint32_t BAUD = 115200;

// IMPORTANT: Set MICROSTEPS to match DM320T DIP microstep selection.
// Example: 64 microsteps -> 12800 steps/rev for a 1.8° motor.
static const uint16_t FULL_STEPS_PER_REV = 200;  // 1.8° motor
static const uint16_t MICROSTEPS         = 64;
static const uint32_t STEPS_PER_REV      = (uint32_t)FULL_STEPS_PER_REV * (uint32_t)MICROSTEPS;

// ----------------------
// GEARING (motor -> output shaft)
// ----------------------
// If the motor-mounted gear (driver) with N teeth drives an output gear with M teeth:
//   output_rev_per_motor_rev = N / M
// For a single external gear mesh (two gears directly meshed), the output direction is reversed.
//
// Set both tooth counts to 1 for direct drive.
#ifndef GEAR_DRIVER_TEETH
//#define GEAR_DRIVER_TEETH 1
#define GEAR_DRIVER_TEETH 54 // Open-Ephys Stepper Motor Gear = 54 teeth
#endif
#ifndef GEAR_DRIVEN_TEETH
//#define GEAR_DRIVEN_TEETH 1
#define GEAR_DRIVEN_TEETH 95 // Open-Ephys Commutator Gear = 95 teeth
#endif

// Direction convention between motor and output:
//   +1 = motor CW produces output CW
//   -1 = motor CW produces output CCW (typical for a single external gear mesh)
#ifndef OUTPUT_DIR_SIGN
//#define OUTPUT_DIR_SIGN (+1)
#define OUTPUT_DIR_SIGN (-1)
#endif

#if (GEAR_DRIVER_TEETH <= 0) || (GEAR_DRIVEN_TEETH <= 0)
#error "GEAR_DRIVER_TEETH and GEAR_DRIVEN_TEETH must be > 0"
#endif
#if (OUTPUT_DIR_SIGN != 1) && (OUTPUT_DIR_SIGN != -1)
#error "OUTPUT_DIR_SIGN must be +1 or -1"
#endif

static uint16_t gearDriverTeeth = (uint16_t)GEAR_DRIVER_TEETH;
static uint16_t gearDrivenTeeth = (uint16_t)GEAR_DRIVEN_TEETH;
static int8_t outputDirSign = (int8_t)OUTPUT_DIR_SIGN;
static float outputRevPerMotorRev = (float)GEAR_DRIVER_TEETH / (float)GEAR_DRIVEN_TEETH;

// DM320T spec: pulse input frequency up to ~60 kHz (hard ceiling).

// ----------------------
// ENABLE TIMING
// ----------------------
// Optional delay between asserting ENA and emitting the first step pulse.
// Some setups benefit from giving the driver/motor current a moment to settle.
static uint16_t preEnableDelayMs = 5;   // set to 0 to disable
static uint32_t enableReadyUs = 0;      // micros() timestamp when it's OK to start stepping
static const float DRIVER_MAX_PULSE_HZ = 60000.0f;

// Default user-programmable rotational speed limit (RPM).
// Typical use: 60–240 RPM. With 64 microsteps, 240 RPM = 51.2 kHz step rate (near the driver's 60 kHz max).
static float rpmLimit = 240.0f;
static const float DEFAULT_MOVE_RPM = 120.0f;

// DM320T timing requirements (manual): minimal pulse width ~7.5us; direction setup ~7.5us.
// Use conservative values.
static const uint32_t PULSE_WIDTH_US = 10;   // >= 7.5us
static const uint32_t DIR_SETUP_US   = 8;    // >= 7.5us

// Keep interval larger than pulse width.
static const uint32_t MIN_INTERVAL_US = PULSE_WIDTH_US + 2;

// ----------------------
// JOYSTICK CONFIG
// ----------------------
static const uint16_t JOY_DEADBAND  = 40;     // ADC counts around center (~4%)
static const uint16_t JOY_SAMPLE_MS = 10;     // sample period
static const float    JOY_LP_ALPHA  = 0.2f;   // low-pass alpha (0..1)

// ----------------------
// STATE
// ----------------------
// Serial TX is made non-blocking during motion by queueing at most one outbound line.
// This prevents Serial.print() from stalling the main loop (which can cause missed steps at high pulse rates).
// Sized for the longest reply (the STATUS line); the printers use the same length.
static const size_t REPLY_BUF_LEN = 240;
static char txLine[REPLY_BUF_LEN];
static uint16_t txLen = 0;
static uint16_t txPos = 0;

static inline bool txBusy() { return txPos < txLen; }
static inline void txClear() { txLen = 0; txPos = 0; }

static inline void txService() {
  if (!txBusy()) return;
  int avail = Serial.availableForWrite();
  while (avail > 0 && txPos < txLen) {
    Serial.write((uint8_t)txLine[txPos++]);
    avail--;
  }
  if (txPos >= txLen) txClear();
}

// Block until the queue is empty. Called wherever dropping or reordering a reply
// would desync a host that reads one line per command.
static inline void txFlush() {
  while (txBusy()) txService();
}

// Replies are formatted directly into txLine rather than into a local buffer:
// a second REPLY_BUF_LEN array on the stack is a quarter of this board's free RAM.
// Format strings live in flash (PSTR), which is what keeps .data near B's footprint.
//
//   n = txBegin();
//   n = txAppend_P(n, PSTR("..."), ...);   // repeat as needed
//   txCommit(n);
//
// or txPrintf_P(PSTR("..."), ...) for a line built in one shot.

static inline size_t txBegin() {
  // Never overwrite an unsent reply: the host is waiting for it.
  txFlush();
  txLine[0] = 0;
  return 0;
}

static size_t txAppend_P(size_t n, PGM_P fmt, ...) {
  if (n >= sizeof(txLine) - 2) return n;
  va_list ap;
  va_start(ap, fmt);
  vsnprintf_P(txLine + n, sizeof(txLine) - 1 - n, fmt, ap);
  va_end(ap);
  // strlen, not vsnprintf's return: that reports what WOULD have been written,
  // so a truncated append would push the next one past the end of the buffer.
  return strlen(txLine);
}

static void txCommit(size_t n) {
  if (n > sizeof(txLine) - 2) n = sizeof(txLine) - 2;
  txLine[n++] = '\n';
  txLine[n] = 0;
  txLen = (uint16_t)n;
  txPos = 0;
}

static void txPrintf_P(PGM_P fmt, ...) {
  size_t n = txBegin();
  va_list ap;
  va_start(ap, fmt);
  vsnprintf_P(txLine, sizeof(txLine) - 1, fmt, ap);
  va_end(ap);
  n = strlen(txLine);
  txCommit(n);
}
enum ControlMode : uint8_t { MODE_USB = 0, MODE_JOY = 1, MODE_AUTO = 2 };
static ControlMode controlMode = MODE_USB;  // default control source

// Avoid name collisions with any accidental symbols named modeName.
static const __FlashStringHelper* modeNameStr(ControlMode m);

static bool driverEnabled = false;

// If true, large/verbose query responses are suppressed while motor is moving.
// Short acknowledgements (OK/ERR) are still queued.
// Default OFF: a host that polls POS?/POSD?/MOVE? during a move expects the value,
// not "BUSY". Turn it on with SERQUIET 1 when step timing matters more than telemetry.
static bool suppressVerboseDuringMotion = false;  // SERQUIET <0|1> / SERQUIET?

static inline bool isMotionActive();

// Auto-enable behavior:
// When motion is commanded (continuous speed != 0 or MOVE active), the driver is enabled.
// When motion stops, the driver is disabled.
static bool motionPermitted = true; // can be forced off via EN 0

// USB setpoint (continuous)
static int8_t usbDirSign = +1;         // +1 = CW, -1 = CCW
static float  usbSpeedMagSps = 0.0f;   // >=0 (microsteps/s)

// Joystick setpoint (continuous)
static int joyCenter = 512;
static float joySpeedSps = 0.0f;       // signed (microsteps/s)
static bool joyOverrideActive = false;
static uint32_t nextJoySampleMs = 0;

// Relative move state (MOVEDEG)
static bool  moveActive = false;
static long  moveTargetPosSteps = 0;   // absolute commanded target position (microsteps)
static float moveSpeedMagSps = 0.0f;   // >=0 (microsteps/s)

// Applied target (what step generator is currently asked to do)
static float targetSpeedSps = 0.0f;    // signed (microsteps/s)
static float lastTargetSpeedSps = 0.0f;
static uint32_t stepIntervalUs = 0;

static inline bool isMotionActive() {
  return (moveActive || (stepIntervalUs != 0 && fabs(targetSpeedSps) >= 0.01f));
}

// Step generator state (software pulse scheduling)
static bool stepPulseActive = false;   // true while STEP is held LOW
static uint32_t pulseEndUs = 0;
static uint32_t nextStepStartUs = 0;
static int8_t currentDirSign = +1;
static uint32_t lastDirChangeUs = 0;

// Commanded position (open-loop count of microsteps)
static long positionSteps = 0;

// Serial input buffer
static const size_t CMD_BUF_LEN = 96;
static char cmdBuf[CMD_BUF_LEN];
static size_t cmdIdx = 0;


// ----------------------
// TIME HELPERS
// ----------------------
static inline bool timeReached(uint32_t now, uint32_t t) {
  return (int32_t)(now - t) >= 0;
}

// ----------------------
// FAST PIN HELPERS
// ----------------------
static inline void stepIdle() {
  if (STEP_IDLE_LEVEL == HIGH) PORTD |=  _BV(STEP_BIT);
  else                         PORTD &= ~_BV(STEP_BIT);
}
static inline void stepActive() {
  if (STEP_ACTIVE_LEVEL == HIGH) PORTD |=  _BV(STEP_BIT);
  else                           PORTD &= ~_BV(STEP_BIT);
}
static inline void dirWriteLevel(uint8_t level) {
  if (level) PORTD |=  _BV(DIR_BIT);
  else       PORTD &= ~_BV(DIR_BIT);
}
static inline void enaWriteLevel(uint8_t level) {
  if (level) PORTD |=  _BV(ENA_BIT);
  else       PORTD &= ~_BV(ENA_BIT);
}

static inline void setDirSign(int8_t sign) {
  currentDirSign = (sign >= 0) ? +1 : -1;
  dirWriteLevel((currentDirSign > 0) ? DIR_CW_LEVEL : DIR_CCW_LEVEL);
  lastDirChangeUs = micros();
}
static inline void onEnableTransition(bool enabled) {
  // Reset scheduling when enabling to avoid stale timestamps.
  if (enabled) {
    stepIdle();
    stepPulseActive = false;
    const uint32_t now = micros();
    nextStepStartUs = now;
    lastDirChangeUs = now;
    enableReadyUs = now + (uint32_t)preEnableDelayMs * 1000UL;
  } else {
    stepIdle();
    stepPulseActive = false;
    enableReadyUs = 0;
  }
}

static inline void setEnable(bool enable) {
  driverEnabled = enable;
  enaWriteLevel(enable ? ENA_ENABLE_LEVEL : ENA_DISABLE_LEVEL);

  // Mirror enable state to TTL output (D5)
  if (enable) PORTD |=  _BV(TTL_EN_BIT);
  else        PORTD &= ~_BV(TTL_EN_BIT);

  onEnableTransition(enable);
}

static inline void autoEnableUpdate(bool needMotion) {
  // needMotion means: we intend to emit step pulses.
  if (!motionPermitted) {
    if (driverEnabled) setEnable(false);
    return;
  }
  if (needMotion && !driverEnabled) setEnable(true);
  if (!needMotion && driverEnabled) setEnable(false);
}

// ----------------------
// LIMITS
// ----------------------
static inline float maxRpmHardware() {
  // Driver pulse ceiling translated to RPM for current microstep setting.
  return (DRIVER_MAX_PULSE_HZ * 60.0f) / (float)STEPS_PER_REV;
}
static inline float clampRpmLimit(float rpm) {
  if (rpm < 0.0f) rpm = -rpm;
  if (rpm < 1.0f) rpm = 1.0f;
  const float hw = maxRpmHardware();
  if (rpm > hw) rpm = hw;
  return rpm;
}
static inline float maxSpsAllowed() {
  // Steps/s allowed by user RPM limit and driver pulse ceiling.
  const float spsFromUser = (rpmLimit * (float)STEPS_PER_REV) / 60.0f;
  return (spsFromUser < DRIVER_MAX_PULSE_HZ) ? spsFromUser : DRIVER_MAX_PULSE_HZ;
}
static inline float clampSpsMag(float spsMag) {
  if (spsMag < 0.0f) spsMag = -spsMag;
  const float maxSps = maxSpsAllowed();
  if (spsMag > maxSps) spsMag = maxSps;
  return spsMag;
}

// ----------------------
// UTIL
// ----------------------
static void strToUpper(char *s) {
  for (size_t i = 0; s[i]; ++i) s[i] = (char)toupper((unsigned char)s[i]);
}

// The Arduino AVR core links avr-libc's integer-only vfprintf: a "%f" conversion
// consumes the argument and emits a bare '?'. Every float in a reply is therefore
// rendered with dtostrf and spliced in as "%s" -- do not reintroduce %f here.
static const size_t FLOAT_BUF_LEN = 20;   // "-34000000.000000" + NUL
static inline char* fmtFloat(char *dst, float v, uint8_t decimals) {
  dtostrf((double)v, 0, decimals, dst);
  return dst;
}

static const __FlashStringHelper* modeNameStr(ControlMode m) {
  switch (m) {
    case MODE_USB:  return F("USB");
    case MODE_JOY:  return F("JOY");
    case MODE_AUTO: return F("AUTO");
    default:        return F("AUTO");
  }
}

static void replyOk() {
  txPrintf_P(PSTR("OK"));
}

// Error text stays in flash: replyErr("...") expands to a PROGMEM literal.
static void replyErr_P(PGM_P m) {
  txPrintf_P(PSTR("ERR %S"), m);
}
#define replyErr(msg) replyErr_P(PSTR(msg))

static inline float stepsToDeg(long steps) {
  // Output-shaft degrees (after gear ratio and optional direction inversion).
  // AVR double == float (32-bit). This is fine for typical step counts; very large counts will lose precision.
  return (float)steps * 360.0f * outputRevPerMotorRev * (float)outputDirSign / (float)STEPS_PER_REV;
}

static inline long degToSteps(float outDeg) {
  // Convert output-shaft degrees -> motor microsteps.
  // outDeg is CW-positive at the output shaft.
  return lroundf(outDeg * (float)STEPS_PER_REV / (360.0f * outputRevPerMotorRev * (float)outputDirSign));
}

static inline void recomputeGear() {
  // Precondition: gearDrivenTeeth > 0
  outputRevPerMotorRev = (float)gearDriverTeeth / (float)gearDrivenTeeth;
}

static void printGear() {
  char rev[FLOAT_BUF_LEN];
  txPrintf_P(PSTR("GEAR DRIVER=%u DRIVEN=%u OUTDIR=%d OUTREV_PER_MOTORREV=%s"),
             (unsigned)gearDriverTeeth, (unsigned)gearDrivenTeeth, (int)outputDirSign,
             fmtFloat(rev, outputRevPerMotorRev, 6));
}

static void printHelp() {
  if (suppressVerboseDuringMotion && isMotionActive()) {
    txPrintf_P(PSTR("BUSY"));
    return;
  }
  Serial.println(F("Commands (newline-terminated):"));
  Serial.println(F("  HELP                : print this help"));
  Serial.println(F("  EN <0|1>             : permit/lock out motion (driver auto-enables around motion). EN? queries"));
  Serial.println(F("  MODE <USB|JOY|AUTO>  : select control source. MODE? queries"));
  Serial.println(F("  DIR <CW|CCW>         : set USB direction. DIR? queries"));
  Serial.println(F("  SPD <steps/s>        : set USB speed in motor microsteps/s (neg flips dir). SPD? queries"));
  Serial.println(F("  RPM <rpm>            : set USB speed in rpm (neg flips dir). RPM? queries"));
  Serial.println(F("  LIMRPM <rpm>         : set rpm ceiling (USB, joystick, MOVE). LIMRPM? queries"));
  Serial.println(F("  ENDELAY <ms>         : pre-enable delay (ms) before stepping. ENDELAY? queries"));
  Serial.println(F("  GEAR <drv> <drn> [outdir] : set gear teeth + output dir sign (+1/-1). GEAR? queries"));
  Serial.println(F("  STOP                : stop motion and cancel MOVE"));
  Serial.println(F("  MOVEDEG <deg> [rpm]  : relative OUTPUT rotation (+CW, -CCW). Optional rpm is MOTOR rpm"));
  Serial.println(F("  MOVE?               : query move state/target/remaining"));
  Serial.println(F("  CANCEL              : cancel MOVE"));
  Serial.println(F("  POS?                : position in microsteps"));
  Serial.println(F("  POSD?               : position in OUTPUT degrees (after gearing)"));
  Serial.println(F("  ZERO                : set position counter to 0"));
  Serial.println(F("  STATUS?             : status line"));
  Serial.println(F("  SERQUIET <0|1>       : reply BUSY to queries while moving (default 0). SERQUIET? queries"));
}

static void printPos() {
  txPrintf_P(PSTR("POS %ld"), positionSteps);
}

static void printPosDeg() {
  char deg[FLOAT_BUF_LEN];
  txPrintf_P(PSTR("POSD %s"), fmtFloat(deg, stepsToDeg(positionSteps), 6));
}

static void printMoveQuery() {
  if (!moveActive) {
    txPrintf_P(PSTR("MOVE 0"));
    return;
  }

  const long remaining = moveTargetPosSteps - positionSteps;
  const float remDeg = stepsToDeg(remaining);
  const float rpm = (moveSpeedMagSps * 60.0f) / (float)STEPS_PER_REV;

  char remDegStr[FLOAT_BUF_LEN];
  char rpmStr[FLOAT_BUF_LEN];

  txPrintf_P(PSTR("MOVE 1 TGT=%ld REM=%ld REMDEG=%s RPM=%s"),
             moveTargetPosSteps, remaining,
             fmtFloat(remDegStr, remDeg, 6), fmtFloat(rpmStr, rpm, 3));
}

static void printStatus() {
  char f[FLOAT_BUF_LEN];   // reused: one float per append

  const float usbSignedSps = (float)usbDirSign * usbSpeedMagSps;
  const float usbRpm = (usbSignedSps * 60.0f) / (float)STEPS_PER_REV;

  // Appended in pieces because each float has to be rendered separately.
  size_t n = txBegin();
  n = txAppend_P(n, PSTR("STATUS EN=%d MODE=%S GEAR=%u/%u OUTDIR=%d ENDELAYMS=%u"),
                 driverEnabled ? 1 : 0,
                 (PGM_P)modeNameStr(controlMode),
                 (unsigned)gearDriverTeeth, (unsigned)gearDrivenTeeth, (int)outputDirSign,
                 (unsigned)preEnableDelayMs);
  n = txAppend_P(n, PSTR(" LIMRPM=%s"),   fmtFloat(f, rpmLimit, 3));
  n = txAppend_P(n, PSTR(" HWMAXRPM=%s"), fmtFloat(f, maxRpmHardware(), 3));
  n = txAppend_P(n, PSTR(" USB_RPM=%s"),  fmtFloat(f, usbRpm, 3));
  n = txAppend_P(n, PSTR(" TGT_SPS=%s"),  fmtFloat(f, targetSpeedSps, 3));
  n = txAppend_P(n, PSTR(" MOVE=%d POS=%ld"), moveActive ? 1 : 0, positionSteps);
  n = txAppend_P(n, PSTR(" POSD=%s"),     fmtFloat(f, stepsToDeg(positionSteps), 6));
  txCommit(n);
}

// ----------------------
// JOYSTICK
// ----------------------
static void calibrateJoystickCenter() {
  long acc = 0;
  const int N = 50;
  for (int i = 0; i < N; ++i) {
    acc += analogRead(PIN_JOY);
    delay(5);
  }
  joyCenter = (int)(acc / N);
}

static void updateJoystick() {
  const uint32_t nowMs = millis();
  if ((int32_t)(nowMs - nextJoySampleMs) < 0) return;
  nextJoySampleMs = nowMs + JOY_SAMPLE_MS;

  const int raw = analogRead(PIN_JOY);
  const int delta = raw - joyCenter;

  joyOverrideActive = (abs(delta) > (int)JOY_DEADBAND);

  if (!joyOverrideActive) {
    joySpeedSps = 0.0f;
    return;
  }

  // Normalize to roughly [-1, 1]
  float norm = (float)delta / 512.0f;
  if (norm > 1.0f) norm = 1.0f;
  if (norm < -1.0f) norm = -1.0f;

  // Cubic shaping for finer control near center
  const float shaped = norm * norm * norm;

  // Map to allowed speed (bounded by rpmLimit)
  const float sps = shaped * maxSpsAllowed();

  // Low-pass filter
  joySpeedSps = (1.0f - JOY_LP_ALPHA) * joySpeedSps + (JOY_LP_ALPHA) * sps;
}

// ----------------------
// LED
// ----------------------
static void updateMotionLed() {
  const bool moving = (moveActive || (stepIntervalUs != 0 && fabs(targetSpeedSps) >= 0.01f));
  digitalWrite(PIN_LED, moving ? HIGH : LOW);
}

static void updateSerialPlotter() {
#if SERIAL_PLOTTER_DEBUG
  const uint32_t nowMs = millis();
  if ((int32_t)(nowMs - nextPlotMs) < 0) return;
  nextPlotMs = nowMs + PLOT_PERIOD_MS;

  // Arduino Serial Plotter-friendly format: two columns -> steps and degrees.
  Serial.print(positionSteps);
  Serial.print('	');
  Serial.println(stepsToDeg(positionSteps), 6);
#endif
}

// ----------------------
// MOVE CONTROL
// ----------------------
static void stopAllMotion(bool cancelMove) {
  if (cancelMove) moveActive = false;

  usbSpeedMagSps = 0.0f;
  joySpeedSps = 0.0f;

  targetSpeedSps = 0.0f;
  lastTargetSpeedSps = 0.0f;
  stepIntervalUs = 0;

  stepIdle();
  stepPulseActive = false;
}

static void beginMoveSteps(long deltaSteps, float rpmMag) {
  
  if (deltaSteps == 0) {
    replyErr("MOVE requires nonzero distance");
    return;
  }

  // Clamp RPM to limit/hardware
  rpmMag = fabs(rpmMag);
  if (rpmMag < 1.0f) rpmMag = 1.0f;
  if (rpmMag > rpmLimit) rpmMag = rpmLimit;

  // Convert to steps/s and clamp
  moveSpeedMagSps = clampSpsMag((rpmMag * (float)STEPS_PER_REV) / 60.0f);

  // Absolute target
  moveTargetPosSteps = positionSteps + deltaSteps;
  moveActive = true;

  // Ensure USB continuous is stopped after completion; we stop it preemptively as well.
  usbSpeedMagSps = 0.0f;

  // Respond with target info
  Serial.print(F("OK MOVE STEPS="));
  Serial.print(deltaSteps);
  Serial.print(F(" TARGET="));
  Serial.print(moveTargetPosSteps);
  Serial.print(F(" RPM="));
  Serial.println(rpmMag, 3);
}

// ----------------------
// SETPOINT SELECTION
// ----------------------
static float computeTargetSpeedSps() {
  // NOTE: Do not gate this on driverEnabled; auto-enable logic uses the result to decide whether to enable.

  if (moveActive) {
    // Signed direction based on remaining distance
    const long remaining = moveTargetPosSteps - positionSteps;
    if (remaining == 0) return 0.0f;
    const int8_t sign = (remaining > 0) ? +1 : -1;
    return (float)sign * moveSpeedMagSps;
  }

  const float usbSigned = (float)usbDirSign * usbSpeedMagSps;

  switch (controlMode) {
    case MODE_USB:
      return usbSigned;
    case MODE_JOY:
      return joySpeedSps;
    case MODE_AUTO:
    default:
      return joyOverrideActive ? joySpeedSps : usbSigned;
  }
}

static void applyTargetSpeed(float newSpeedSps) {
  // Clamp to allowed max (both user limit and driver ceiling)
  const float maxSps = maxSpsAllowed();
  if (newSpeedSps >  maxSps) newSpeedSps =  maxSps;
  if (newSpeedSps < -maxSps) newSpeedSps = -maxSps;

  // Snap tiny values to zero
  if (fabs(newSpeedSps) < 0.01f) newSpeedSps = 0.0f;

  // Update interval only when speed changes significantly
  if (fabs(newSpeedSps - lastTargetSpeedSps) > 0.01f) {
    lastTargetSpeedSps = newSpeedSps;

    const float absSps = fabs(newSpeedSps);
    if (absSps < 0.01f) {
      stepIntervalUs = 0;
    } else {
      uint32_t interval = (uint32_t)(1000000.0f / absSps + 0.5f);
      if (interval < MIN_INTERVAL_US) interval = MIN_INTERVAL_US;
      stepIntervalUs = interval;

      // If we were stopped, start immediately
      if (fabs(targetSpeedSps) < 0.01f) nextStepStartUs = micros();
    }
  }

  targetSpeedSps = newSpeedSps;
}

// ----------------------
// STEP GENERATOR
// ----------------------
static void updateStepGenerator() {
  const uint32_t nowUs = micros();

  // If stopped/disabled: keep STEP idle and do nothing.
  if (!driverEnabled || fabs(targetSpeedSps) < 0.01f || stepIntervalUs == 0) {
    if (stepPulseActive) {
      stepIdle();
      stepPulseActive = false;
    } else {
      stepIdle();
    }
    return;
  }

  // Update DIR if sign changed.
  const int8_t desiredDirSign = (targetSpeedSps >= 0.0f) ? +1 : -1;
  if (desiredDirSign != currentDirSign) {
    // Only change DIR when STEP is idle high.
    if (!stepPulseActive) {
      setDirSign(desiredDirSign);
      // Ensure next step won't occur until DIR setup time has passed.
      const uint32_t earliest = lastDirChangeUs + DIR_SETUP_US;
      if (timeReached(nowUs, nextStepStartUs) && !timeReached(nowUs, earliest)) {
        nextStepStartUs = earliest;
      }
    }
  }

  if (!stepPulseActive) {
    // Wait until: (a) pre-enable delay has elapsed (if any), (b) time to start LOW pulse,
    // and (c) DIR setup time has elapsed.
    if (enableReadyUs != 0 && !timeReached(nowUs, enableReadyUs)) {
      stepIdle();
      return;
    }
    const uint32_t earliest = lastDirChangeUs + DIR_SETUP_US;
    if (timeReached(nowUs, nextStepStartUs) && timeReached(nowUs, earliest)) {
      stepActive();
      stepPulseActive = true;
      pulseEndUs = nowUs + PULSE_WIDTH_US;
    }
    return;
  }

  // Pulse is active LOW; end it at pulseEndUs to create the rising edge.
  if (timeReached(nowUs, pulseEndUs)) {
    stepIdle();
    stepPulseActive = false;

    // Rising edge occurred: update position.
    positionSteps += (long)currentDirSign;

    // If a MOVE is active, stop exactly on target.
    if (moveActive && positionSteps == moveTargetPosSteps) {
      moveActive = false;
      stopAllMotion(false);  // stops continuous setpoints too
      return;
    }

    // Schedule next pulse start so that the NEXT rising edge is stepIntervalUs later.
    const uint32_t nextRisingUs = nowUs + stepIntervalUs;
    nextStepStartUs = nextRisingUs - PULSE_WIDTH_US;
  }
}

// ----------------------
// SERIAL COMMAND HANDLING
// ----------------------
static void processLine(char *line) {
  // Trim leading spaces
  while (*line == ' ' || *line == '	') line++;
  if (*line == 0) return;

  // Tokenize
  char *cmd = strtok(line, " 	");
  if (!cmd) return;

  // Detect query suffix (e.g., POS?)
  bool isQuery = false;
  size_t n = strlen(cmd);
  if (n > 0 && cmd[n - 1] == '?') {
    cmd[n - 1] = 0;
    isQuery = true;
  }

  strToUpper(cmd);

  // HELP
  if (strcmp_P(cmd, PSTR("HELP")) == 0) { printHelp(); return; }

  // EN
  if (strcmp_P(cmd, PSTR("EN")) == 0) {
    if (isQuery) {
      // Report motion permission and instantaneous enable state.
      Serial.print(F("EN "));
      Serial.print(motionPermitted ? 1 : 0);
      Serial.print(F(" ACTUAL "));
      Serial.println(driverEnabled ? 1 : 0);
      return;
    }

    char *arg = strtok(NULL, " 	");
    if (!arg) { replyErr("EN requires 0 or 1"); return; }
    int v = atoi(arg);

    motionPermitted = (v != 0);
    if (!motionPermitted) {
      stopAllMotion(true);
      setEnable(false);
    }

    replyOk();
    return;
  }

  // MODE
  if (strcmp_P(cmd, PSTR("MODE")) == 0) {
    if (isQuery) {
      Serial.print(F("MODE "));
      Serial.println(modeNameStr(controlMode));
      return;
    }
    char *arg = strtok(NULL, " 	");
    if (!arg) { replyErr("MODE requires USB, JOY, or AUTO"); return; }
    strToUpper(arg);
    if      (strcmp_P(arg, PSTR("USB"))  == 0) controlMode = MODE_USB;
    else if (strcmp_P(arg, PSTR("JOY"))  == 0) controlMode = MODE_JOY;
    else if (strcmp_P(arg, PSTR("AUTO")) == 0) controlMode = MODE_AUTO;
    else { replyErr("MODE must be USB, JOY, or AUTO"); return; }
    replyOk();
    return;
  }

  // DIR
  if (strcmp_P(cmd, PSTR("DIR")) == 0) {
    if (isQuery) {
      Serial.print(F("DIR "));
      Serial.println((usbDirSign > 0) ? F("CW") : F("CCW"));
      return;
    }
    char *arg = strtok(NULL, " 	");
    if (!arg) { replyErr("DIR requires CW or CCW"); return; }
    strToUpper(arg);
    if      (strcmp_P(arg, PSTR("CW"))  == 0) usbDirSign = +1;
    else if (strcmp_P(arg, PSTR("CCW")) == 0) usbDirSign = -1;
    else { replyErr("DIR must be CW or CCW"); return; }
    replyOk();
    return;
  }

  // LIMRPM
  if (strcmp_P(cmd, PSTR("LIMRPM")) == 0) {
    if (isQuery) {
      Serial.print(F("LIMRPM "));
      Serial.println(rpmLimit, 3);
      return;
    }
    char *arg = strtok(NULL, " 	");
    if (!arg) { replyErr("LIMRPM requires a numeric RPM"); return; }
    float v = atof(arg);
    rpmLimit = clampRpmLimit(v);

    // Clamp any existing setpoints to the new limit
    usbSpeedMagSps = clampSpsMag(usbSpeedMagSps);
    moveSpeedMagSps = clampSpsMag(moveSpeedMagSps);

    Serial.print(F("OK LIMRPM "));
    Serial.println(rpmLimit, 3);
    return;
  }

  // ENDELAY
  if (strcmp_P(cmd, PSTR("ENDELAY")) == 0) {
    if (isQuery) {
      txPrintf_P(PSTR("ENDELAY %u"), (unsigned)preEnableDelayMs);
      return;
    }
    char *arg = strtok(NULL, " 	");
    if (!arg) { replyErr("ENDELAY requires integer ms (0..60000)"); return; }
    long v = atol(arg);
    if (v < 0 || v > 60000) { replyErr("ENDELAY must be 0..60000"); return; }
    preEnableDelayMs = (uint16_t)v;
    replyOk();
    return;
  }

  // SERQUIET
  if (strcmp_P(cmd, PSTR("SERQUIET")) == 0) {
    if (isQuery) {
      txPrintf_P(PSTR("SERQUIET %d"), suppressVerboseDuringMotion ? 1 : 0);
      return;
    }
    char *arg = strtok(NULL, " 	");
    if (!arg) { replyErr("SERQUIET requires 0 or 1"); return; }
    int v = atoi(arg);
    suppressVerboseDuringMotion = (v != 0);
    replyOk();
    return;
  }

  // GEAR
  if (strcmp_P(cmd, PSTR("GEAR")) == 0) {
    if (isQuery) {
      if (suppressVerboseDuringMotion && isMotionActive()) { txPrintf_P(PSTR("BUSY")); return; }
      printGear();
      return;
    }

    if (moveActive) {
      replyErr("Cannot change GEAR during MOVE (send STOP/CANCEL first)");
      return;
    }

    char *a = strtok(NULL, " 	");
    char *b = strtok(NULL, " 	");
    if (!a || !b) {
      replyErr("GEAR requires: GEAR <driver_teeth> <driven_teeth> [outdir] (outdir=+1 or -1)");
      return;
    }

    long drv = atol(a);
    long drn = atol(b);
    if (drv <= 0 || drv > 65535L || drn <= 0 || drn > 65535L) {
      replyErr("GEAR teeth must be in 1..65535");
      return;
    }

    int8_t s = outputDirSign;
    char *c = strtok(NULL, " 	");
    if (c) {
      int si = atoi(c);
      if (si != 1 && si != -1) {
        replyErr("GEAR outdir must be +1 or -1");
        return;
      }
      s = (int8_t)si;
    }

    gearDriverTeeth = (uint16_t)drv;
    gearDrivenTeeth = (uint16_t)drn;
    outputDirSign = s;
    recomputeGear();

    Serial.print(F("OK "));
    printGear();
    return;
  }

  // SPD (steps per second)
  if (strcmp_P(cmd, PSTR("SPD")) == 0) {
    if (isQuery) {
      Serial.print(F("SPD "));
      Serial.println(usbDirSign * usbSpeedMagSps, 3);
      return;
    }
    char *arg = strtok(NULL, " 	");
    if (!arg) { replyErr("SPD requires numeric steps/s"); return; }
    float v = atof(arg);
    if (v < 0.0f) { usbDirSign = -1; v = -v; }
    usbSpeedMagSps = clampSpsMag(v);
    replyOk();
    return;
  }

  // RPM (continuous)
  if (strcmp_P(cmd, PSTR("RPM")) == 0) {
    if (isQuery) {
      const float signedSps = (float)usbDirSign * usbSpeedMagSps;
      const float rpm = (signedSps * 60.0f) / (float)STEPS_PER_REV;
      Serial.print(F("RPM "));
      Serial.println(rpm, 3);
      return;
    }
    char *arg = strtok(NULL, " 	");
    if (!arg) { replyErr("RPM requires a numeric value"); return; }
    float rpm = atof(arg);
    if (rpm < 0.0f) { usbDirSign = -1; rpm = -rpm; }
    if (rpm > rpmLimit) rpm = rpmLimit;

    usbSpeedMagSps = clampSpsMag((rpm * (float)STEPS_PER_REV) / 60.0f);
    replyOk();
    return;
  }

  // MOVEDEG <deg> [rpm]
  if (strcmp_P(cmd, PSTR("MOVEDEG")) == 0) {
    if (isQuery) { replyErr("MOVEDEG? not supported; use MOVE? and POS?/POSD?"); return; }

    char *degArg = strtok(NULL, " 	");
    if (!degArg) { replyErr("MOVEDEG requires degrees"); return; }
    const float deg = atof(degArg);
    if (fabs(deg) < 1e-6f) { replyErr("MOVEDEG requires nonzero degrees"); return; }

    // Convert OUTPUT degrees to motor microsteps (accounts for gear ratio and OUTPUT_DIR_SIGN).
    long deltaSteps = degToSteps(deg);

    // Guarantee at least 1 step for small nonzero degrees.
    if (deltaSteps == 0) deltaSteps = (deg > 0.0f) ? 1L : -1L;

    // Optional rpm argument
    float rpmMag = 0.0f;
    char *rpmArg = strtok(NULL, " 	");
    if (rpmArg) {
      rpmMag = fabs(atof(rpmArg));
    } else {
      // Use current USB RPM if nonzero; otherwise a default.
      float usbRpmMag = (usbSpeedMagSps * 60.0f) / (float)STEPS_PER_REV;
      rpmMag = (usbRpmMag >= 1.0f) ? usbRpmMag : DEFAULT_MOVE_RPM;
    }

    beginMoveSteps(deltaSteps, rpmMag);
    return;
  }

  // MOVE?
  if (strcmp_P(cmd, PSTR("MOVE")) == 0) {
    if (!isQuery) { replyErr("Use MOVEDEG to command motion; MOVE? to query"); return; }
    if (suppressVerboseDuringMotion && isMotionActive()) { txPrintf_P(PSTR("BUSY")); return; }
    printMoveQuery();
    return;
  }

  // CANCEL
  if (strcmp_P(cmd, PSTR("CANCEL")) == 0) {
    if (moveActive) {
      moveActive = false;
      stopAllMotion(false);
    }
    replyOk();
    return;
  }

  // STOP
  if (strcmp_P(cmd, PSTR("STOP")) == 0) {
    stopAllMotion(true);
    replyOk();
    return;
  }

  // POS
  if (strcmp_P(cmd, PSTR("POS")) == 0) {
    if (suppressVerboseDuringMotion && isMotionActive()) { txPrintf_P(PSTR("BUSY")); return; }
    printPos();
    return;
  }

  // POSD
  if (strcmp_P(cmd, PSTR("POSD")) == 0) {
    if (suppressVerboseDuringMotion && isMotionActive()) { txPrintf_P(PSTR("BUSY")); return; }
    printPosDeg();
    return;
  }

  // ZERO
  if (strcmp_P(cmd, PSTR("ZERO")) == 0) { positionSteps = 0; replyOk(); return; }

  // STATUS
  if (strcmp_P(cmd, PSTR("STATUS")) == 0) {
    if (suppressVerboseDuringMotion && isMotionActive()) { txPrintf_P(PSTR("BUSY")); return; }
    printStatus();
    return;
  }

  replyErr("Unknown command. Send HELP.");
}

static void handleSerial() {
  while (Serial.available() > 0) {
    const char c = (char)Serial.read();

    // Treat either CR or LF as end-of-line. (Many terminals send CRLF.)
    if (c == '\n' || c == '\r') {
      if (cmdIdx > 0) {
        cmdBuf[cmdIdx] = 0;
        // Some handlers reply through the queue and others print directly; drain
        // first so the previous command's reply cannot be overtaken by this one's.
        txFlush();
        processLine(cmdBuf);
        cmdIdx = 0;
      }
      continue;
    }

    if (cmdIdx < CMD_BUF_LEN - 1) {
      cmdBuf[cmdIdx++] = c;
    } else {
      cmdIdx = 0;
      replyErr("Input line too long");
    }
  }
}

// ----------------------
// SETUP / LOOP
// ----------------------
void setup() {
  Serial.begin(BAUD);
#if SERIAL_PLOTTER_DEBUG
  nextPlotMs = millis();
#endif

  // Configure STEP/DIR/ENA pins as output with direct DDR writes.
  DDRD |= _BV(STEP_BIT) | _BV(DIR_BIT) | _BV(ENA_BIT) | _BV(TTL_EN_BIT);

  // LED
  pinMode(PIN_LED, OUTPUT);

  // TTL enable mirror (initialize LOW)
  digitalWrite(PIN_TTL_EN, LOW);
  digitalWrite(PIN_LED, LOW);

  stepIdle();
  setDirSign(+1);

  // Start disabled; driver will auto-enable immediately before motion.
  setEnable(false);

  rpmLimit = clampRpmLimit(rpmLimit);

  // Initialize gear ratio from defaults
  gearDriverTeeth = (uint16_t)GEAR_DRIVER_TEETH;
  gearDrivenTeeth = (uint16_t)GEAR_DRIVEN_TEETH;
  outputDirSign = (int8_t)OUTPUT_DIR_SIGN;
  if (gearDrivenTeeth == 0) gearDrivenTeeth = 1;
  if (outputDirSign != 1 && outputDirSign != -1) outputDirSign = 1;
  recomputeGear();

  calibrateJoystickCenter();
  nextJoySampleMs = millis();

  Serial.println(F("DM320T stepper controller ready. Send HELP."));
}

void loop() {
  // Always service outgoing serial first to avoid TX buffer buildup.
  txService();

  handleSerial();

  // Avoid analogRead() stalls in MODE_USB (can cause step timing jitter at high pulse rates)
  if (controlMode != MODE_USB) {
    updateJoystick();
  } else {
    joyOverrideActive = false;
    joySpeedSps = 0.0f;
  }

  const float newTarget = computeTargetSpeedSps();
  applyTargetSpeed(newTarget);

  // Auto-enable just before motion, auto-disable just after motion.
  const bool needMotion = (moveActive || (stepIntervalUs != 0 && fabs(targetSpeedSps) >= 0.01f));
  autoEnableUpdate(needMotion);

  updateStepGenerator();

  updateMotionLed();
  updateSerialPlotter();

  // Service serial again at end of loop (cheap) to flush queued line.
  txService();
}
