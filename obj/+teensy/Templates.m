classdef Templates
    % teensy.Templates
    % Ready-made operant paradigms for the Teensy Trial Designer.
    %
    % Each template is a complete, valid teensy.Program with its diagram laid
    % out and every duration exposed as a variable, so a researcher can open
    % one, retarget its channels to their box, and run it. Starting from a
    % working paradigm and editing it is far more reliable than assembling a
    % state machine from an empty canvas, which is why the designer's New
    % dialog leads with this list.
    %
    % Methods
    %   list  - Table of the available templates.
    %   names - String array of template names.
    %   get   - Build one template as a teensy.Program.
    %
    % Example
    %   disp(teensy.Templates.list())
    %   p = teensy.Templates.get("GoNoGoDetection");
    %   teensy.TrialDesigner(p);
    %
    % See also: teensy.Program, teensy.TrialDesigner,
    %           documentation/teensy/teensy_Templates.md

    methods (Static)

        function T = list()
            % T = teensy.Templates.list()
            % Describe every available template.
            %
            % Returns:
            %   T - Table with Name, Title, Description and Tags.
            rows = {
                "Blank", "Empty program", ...
                    "One idle state and the default channel set. Start from scratch.", "basic"
                "GoNoGoDetection", "Go / No-Go detection", ...
                    "Signal and catch trials with hit, miss, correct reject, false alarm and abort.", "detection psychophysics"
                "TwoAlternativeForcedChoice", "Two-alternative forced choice", ...
                    "Center initiation, then a left or right choice scored against the trial type.", "discrimination choice"
                "FixedRatio", "Fixed ratio", ...
                    "N responses on the active operandum deliver a reward.", "operant schedule"
                "NosePokeShaping", "Nose-poke shaping", ...
                    "Autoshaping: any poke is rewarded, and free rewards keep a naive animal engaged.", "training shaping"
                "PassiveExposure", "Passive exposure", ...
                    "No contingency; a cue and a sync pulse on a fixed interval.", "control passive"
                };

            T = table(string(rows(:, 1)), string(rows(:, 2)), string(rows(:, 3)), string(rows(:, 4)), ...
                VariableNames = {'Name', 'Title', 'Description', 'Tags'});
        end

        function n = names()
            % n = teensy.Templates.names()
            % Names of the available templates.
            n = teensy.Templates.list().Name';
        end

        function p = get(name)
            % p = teensy.Templates.get(name)
            % Build a template.
            %
            % Parameters
            %   name - One of teensy.Templates.names().
            %
            % Returns:
            %   p - A laid-out teensy.Program that passes validate() with no
            %       error-severity issues.
            arguments
                name (1,1) string = "Blank"
            end

            switch name
                case "GoNoGoDetection"
                    p = teensy.Templates.goNoGoDetection_();
                case "TwoAlternativeForcedChoice"
                    p = teensy.Templates.twoAFC_();
                case "FixedRatio"
                    p = teensy.Templates.fixedRatio_();
                case "NosePokeShaping"
                    p = teensy.Templates.nosePokeShaping_();
                case "PassiveExposure"
                    p = teensy.Templates.passiveExposure_();
                otherwise
                    p = teensy.Templates.blank_();
            end

            p.autoLayout();
            p.clearDirty();
        end
    end

    methods (Static, Access = private)

        function p = blank_()
            % p = blank_()
            % One idle state and the default channel set.
            p = teensy.Program(Name = "Untitled", ...
                Description = "A new program.");
            p.Channels = teensy.Channel.defaultSet();

            idle = teensy.State("Idle", DurationMs = 1000, ...
                Notes = "Waiting. Add transitions to build the paradigm.");
            p.addState(idle);

            done = teensy.State("Done", IsTerminal = true, ...
                RespCodeBits = epsych.BitMask.Abort, ...
                Notes = "Ends the trial. Change its response bits to the outcome you mean.");
            p.addState(done);

            p.States(1).Transitions(end+1) = teensy.Transition.to("Done", ...
                teensy.Condition.timerElapsed());
            p.StartState = "Idle";
        end

        function p = goNoGoDetection_()
            % p = goNoGoDetection_()
            % The classic detection task: respond on signal, withhold on catch.
            %
            % TrialType_0 is a signal trial and TrialType_1 a catch trial,
            % matching how cl_AppetitiveDetection_BoxGUI decodes them, so the
            % shipped psychophysics.Detection analysis works unmodified.
            p = teensy.Program(Name = "GoNoGoDetection", ...
                Description = "Signal and catch trials scored as hit, miss, correct reject or false alarm.");
            p.Channels = teensy.Channel.defaultSet();

            teensy.Templates.addVars_(p, {
                "P_Catch",    0.3,    0,     1,  "",   "Probability of a catch trial. Set it to 0 or 1 from the trial table to force one kind."
                "ITIDur",    3000,  100, 60000, "ms", "Inter-trial interval."
                "StimDelay",  500,    0, 10000, "ms", "Delay from trial start to the cue."
                "StimDur",    500,   10, 10000, "ms", "Cue duration."
                "RespWinDur",2000,  100, 30000, "ms", "How long a response is accepted."
                "RewardDur",   40,    1,  1000, "ms", "Reward valve open time."
                "TimeoutDur",5000,    0, 60000, "ms", "Penalty after a false alarm."
                });

            p.addState(teensy.State("ITI", DurationMs = "@ITIDur", ...
                Notes = "Inter-trial interval. Nothing is scored here."));

            p.addState(teensy.State("PreStim", DurationMs = "@StimDelay", ...
                Notes = "Silent delay before the cue. A response here is an abort."));

            p.addState(teensy.State("Stimulus", DurationMs = "@StimDur", ...
                Notes = "The cue is on. Signal trials only."));

            p.addState(teensy.State("RespWindow", DurationMs = "@RespWinDur", ...
                RespCodeBits = epsych.BitMask.ResponseWindow, ...
                Notes = "Signal trial. A response here is a hit, silence is a miss."));

            p.addState(teensy.State("CatchWindow", DurationMs = "@RespWinDur", ...
                RespCodeBits = epsych.BitMask.ResponseWindow, ...
                Notes = "Catch trial: no cue was presented. A response here is a false alarm."));

            p.addState(teensy.State("Hit", IsTerminal = true, ...
                RespCodeBits = [epsych.BitMask.Hit, epsych.BitMask.Reward, epsych.BitMask.TrialType_0], ...
                Notes = "Responded on a signal trial. Reward delivered."));

            p.addState(teensy.State("Miss", IsTerminal = true, ...
                RespCodeBits = [epsych.BitMask.Miss, epsych.BitMask.TrialType_0], ...
                Notes = "No response on a signal trial."));

            p.addState(teensy.State("FalseAlarm", IsTerminal = true, ...
                RespCodeBits = [epsych.BitMask.FalseAlarm, epsych.BitMask.Punish, epsych.BitMask.TrialType_1], ...
                Notes = "Responded on a catch trial. Timeout penalty."));

            p.addState(teensy.State("CorrectReject", IsTerminal = true, ...
                RespCodeBits = [epsych.BitMask.CorrectReject, epsych.BitMask.TrialType_1], ...
                Notes = "Correctly withheld on a catch trial."));

            p.addState(teensy.State("Abort", IsTerminal = true, ...
                RespCodeBits = epsych.BitMask.Abort, ...
                Notes = "Responded before the response window opened."));

            p.StartState = "ITI";

            % Wiring is done by name rather than by index so inserting a state
            % above cannot silently rewire the paradigm.
            add = @(from, transition) teensy.Templates.addTransition_(p, from, transition);
            entry = @(state, action) teensy.Templates.addEntry_(p, state, action);
            exit = @(state, action) teensy.Templates.addExit_(p, state, action);

            add("ITI", teensy.Transition.to("PreStim", teensy.Condition.timerElapsed()));

            % An early response aborts. Otherwise the trial splits into a signal
            % or a catch trial. Branching on a probability rather than reading a
            % trial-type variable is deliberate: the host can set P_Catch to 0 or
            % 1 from the trial table to force either kind, and to anything in
            % between to let the board randomize.
            add("PreStim", teensy.Transition.to("Abort", ...
                teensy.Condition.digitalEdge("Poke", "Rising")));
            add("PreStim", teensy.Transition.to("CatchWindow", ...
                teensy.Condition.all([teensy.Condition.timerElapsed(), ...
                    teensy.Condition.probability("@P_Catch")])));
            add("PreStim", teensy.Transition.to("Stimulus", teensy.Condition.timerElapsed()));

            entry("Stimulus", teensy.Action.setOutput("HouseLight", 1));
            entry("Stimulus", teensy.Action.sync("Sync", 5));
            exit("Stimulus", teensy.Action.setOutput("HouseLight", 0));
            add("Stimulus", teensy.Transition.to("RespWindow", teensy.Condition.timerElapsed()));

            % Order matters here: the response is tested before the timer, so a
            % response landing on the last tick of the window still counts.
            add("RespWindow", teensy.Transition.to("Hit", ...
                teensy.Condition.digitalEdge("Poke", "Rising")));
            add("RespWindow", teensy.Transition.to("Miss", teensy.Condition.timerElapsed()));

            add("CatchWindow", teensy.Transition.to("FalseAlarm", ...
                teensy.Condition.digitalEdge("Poke", "Rising")));
            add("CatchWindow", teensy.Transition.to("CorrectReject", ...
                teensy.Condition.timerElapsed()));

            entry("Hit", teensy.Action.markLatency());
            entry("Hit", teensy.Action.pulse("Reward", "@RewardDur"));

            entry("FalseAlarm", teensy.Action.markLatency());
            entry("FalseAlarm", teensy.Action.pulse("HouseLight", "@TimeoutDur"));

            entry("Abort", teensy.Action.markLatency());
        end

        function p = twoAFC_()
            % p = twoAFC_()
            % Center poke initiates; a left or right choice is scored.
            p = teensy.Program(Name = "TwoAlternativeForcedChoice", ...
                Description = "Center initiation, then a left or right choice scored against the trial type.");

            p.Channels = [ ...
                teensy.Channel.digitalIn("Center", 2, DebounceMs = 5), ...
                teensy.Channel.digitalIn("Left", 3, DebounceMs = 5), ...
                teensy.Channel.digitalIn("Right", 4, DebounceMs = 5), ...
                teensy.Channel.digitalOut("RewardL", 5), ...
                teensy.Channel.digitalOut("RewardR", 6), ...
                teensy.Channel.digitalOut("HouseLight", 7, IdleState = 1), ...
                teensy.Channel.digitalOut("Sync", 8)];

            teensy.Templates.addVars_(p, {
                "TrialType",   0,   0,     1,  "",   "0 = left is correct, 1 = right is correct."
                "ITIDur",   2000, 100, 60000, "ms", "Inter-trial interval."
                "HoldDur",   300,   0,  5000, "ms", "How long the center poke must be held."
                "ChoiceDur",3000, 100, 30000, "ms", "Time allowed to make a choice."
                "RewardDur",  40,   1,  1000, "ms", "Reward valve open time."
                "TimeoutDur",4000,  0, 60000, "ms", "Penalty after an error."
                });

            p.addState(teensy.State("ITI", DurationMs = "@ITIDur", ...
                Notes = "Inter-trial interval."));
            p.addState(teensy.State("WaitInit", DurationMs = Inf, ...
                Notes = "Waiting for the animal to poke the center port."));
            p.addState(teensy.State("Hold", DurationMs = "@HoldDur", ...
                Notes = "Center poke must be held. Leaving early aborts."));
            p.addState(teensy.State("Choice", DurationMs = "@ChoiceDur", ...
                RespCodeBits = epsych.BitMask.ResponseWindow, ...
                Notes = "Left or right. The first port entered wins."));
            p.addState(teensy.State("ChoseLeft", IsTerminal = true, ...
                RespCodeBits = [epsych.BitMask.Hit, epsych.BitMask.Reward, epsych.BitMask.Choice_0], ...
                Notes = "Chose left. Scored correct when TrialType is 0."));
            p.addState(teensy.State("ChoseRight", IsTerminal = true, ...
                RespCodeBits = [epsych.BitMask.Hit, epsych.BitMask.Reward, epsych.BitMask.Choice_1], ...
                Notes = "Chose right. Scored correct when TrialType is 1."));
            p.addState(teensy.State("NoChoice", IsTerminal = true, ...
                RespCodeBits = epsych.BitMask.Miss, ...
                Notes = "The choice window closed with no response."));
            p.addState(teensy.State("Abort", IsTerminal = true, ...
                RespCodeBits = epsych.BitMask.Abort, ...
                Notes = "Left the center port before the hold completed."));

            p.StartState = "ITI";

            p.States(1).Transitions(end+1) = teensy.Transition.to("WaitInit", ...
                teensy.Condition.timerElapsed());

            p.States(2).EntryActions(end+1) = teensy.Action.setOutput("HouseLight", 0);
            p.States(2).Transitions(end+1) = teensy.Transition.to("Hold", ...
                teensy.Condition.digitalEdge("Center", "Rising"));

            p.States(3).Transitions(end+1) = teensy.Transition.to("Abort", ...
                teensy.Condition.digitalEdge("Center", "Falling"));
            p.States(3).Transitions(end+1) = teensy.Transition.to("Choice", ...
                teensy.Condition.timerElapsed());

            p.States(4).EntryActions(end+1) = teensy.Action.sync("Sync", 5);
            p.States(4).Transitions(end+1) = teensy.Transition.to("ChoseLeft", ...
                teensy.Condition.digitalEdge("Left", "Rising"));
            p.States(4).Transitions(end+1) = teensy.Transition.to("ChoseRight", ...
                teensy.Condition.digitalEdge("Right", "Rising"));
            p.States(4).Transitions(end+1) = teensy.Transition.to("NoChoice", ...
                teensy.Condition.timerElapsed());

            p.States(5).EntryActions(end+1) = teensy.Action.markLatency();
            p.States(5).EntryActions(end+1) = teensy.Action.pulse("RewardL", "@RewardDur");
            p.States(6).EntryActions(end+1) = teensy.Action.markLatency();
            p.States(6).EntryActions(end+1) = teensy.Action.pulse("RewardR", "@RewardDur");
            p.States(8).EntryActions(end+1) = teensy.Action.markLatency();
        end

        function p = fixedRatio_()
            % p = fixedRatio_()
            % N responses on the active operandum deliver a reward.
            p = teensy.Program(Name = "FixedRatio", ...
                Description = "A fixed number of responses delivers one reward.");
            p.Channels = teensy.Channel.defaultSet();

            teensy.Templates.addVars_(p, {
                "FRatio",      5,   1,   500,  "",   "Responses required per reward."
                "ITIDur",   2000, 100, 60000, "ms", "Inter-trial interval."
                "SessionDur", 60000, 1000, 600000, "ms", "How long a trial may run before it times out."
                "RewardDur",  40,   1,  1000, "ms", "Reward valve open time."
                });

            p.addCounter("Responses", "Poke", "Rising");

            p.addState(teensy.State("ITI", DurationMs = "@ITIDur", ...
                Notes = "Inter-trial interval. The counter is cleared on the way out."));
            p.addState(teensy.State("Responding", DurationMs = "@SessionDur", ...
                Notes = "Counting responses until the ratio is met."));
            p.addState(teensy.State("Rewarded", IsTerminal = true, ...
                RespCodeBits = [epsych.BitMask.Hit, epsych.BitMask.Reward], ...
                Notes = "The ratio was completed and the reward delivered."));
            p.addState(teensy.State("TimedOut", IsTerminal = true, ...
                RespCodeBits = epsych.BitMask.Miss, ...
                Notes = "The trial expired before the ratio was completed."));

            p.StartState = "ITI";

            p.States(1).ExitActions(end+1) = teensy.Action.resetCounter("Responses");
            p.States(1).Transitions(end+1) = teensy.Transition.to("Responding", ...
                teensy.Condition.timerElapsed());

            p.States(2).EntryActions(end+1) = teensy.Action.setOutput("HouseLight", 1);
            p.States(2).Transitions(end+1) = teensy.Transition.to("Rewarded", ...
                teensy.Condition.counterReached("Responses", "GE", "@FRatio"));
            p.States(2).Transitions(end+1) = teensy.Transition.to("TimedOut", ...
                teensy.Condition.timerElapsed());

            p.States(3).EntryActions(end+1) = teensy.Action.markLatency();
            p.States(3).EntryActions(end+1) = teensy.Action.pulse("Reward", "@RewardDur");
            p.States(3).EntryActions(end+1) = teensy.Action.setOutput("HouseLight", 0);
            p.States(4).EntryActions(end+1) = teensy.Action.setOutput("HouseLight", 0);
        end

        function p = nosePokeShaping_()
            % p = nosePokeShaping_()
            % Autoshaping: any poke pays, and free rewards keep a naive animal
            % coming back to the port.
            p = teensy.Program(Name = "NosePokeShaping", ...
                Description = "Any poke is rewarded; free rewards are delivered if the animal does not respond.");
            p.Channels = teensy.Channel.defaultSet();

            teensy.Templates.addVars_(p, {
                "ITIDur",     2000, 100, 60000, "ms", "Inter-trial interval."
                "WaitDur",   20000, 100, 300000, "ms", "How long to wait for a poke before giving a free reward."
                "RewardDur",    40,   1,  1000, "ms", "Reward valve open time."
                "CueDur",      500,  10, 10000, "ms", "How long the port light stays on as a lure."
                });

            p.addState(teensy.State("ITI", DurationMs = "@ITIDur", ...
                Notes = "Inter-trial interval."));
            p.addState(teensy.State("Lure", DurationMs = "@WaitDur", ...
                Notes = "Port light on. Any poke pays; if none comes, a free reward is given."));
            p.addState(teensy.State("Earned", IsTerminal = true, ...
                RespCodeBits = [epsych.BitMask.Hit, epsych.BitMask.Reward], ...
                Notes = "The animal poked and was rewarded."));
            p.addState(teensy.State("Free", IsTerminal = true, ...
                RespCodeBits = [epsych.BitMask.Reward, epsych.BitMask.Option_A], ...
                Notes = "No poke, so a free reward was delivered. Option_A marks it as unearned."));

            p.StartState = "ITI";

            p.States(1).Transitions(end+1) = teensy.Transition.to("Lure", ...
                teensy.Condition.timerElapsed());

            p.States(2).EntryActions(end+1) = teensy.Action.pulse("HouseLight", "@CueDur");
            p.States(2).Transitions(end+1) = teensy.Transition.to("Earned", ...
                teensy.Condition.digitalEdge("Poke", "Rising"));
            p.States(2).Transitions(end+1) = teensy.Transition.to("Free", ...
                teensy.Condition.timerElapsed());

            p.States(3).EntryActions(end+1) = teensy.Action.markLatency();
            p.States(3).EntryActions(end+1) = teensy.Action.pulse("Reward", "@RewardDur");
            p.States(4).EntryActions(end+1) = teensy.Action.pulse("Reward", "@RewardDur");
        end

        function p = passiveExposure_()
            % p = passiveExposure_()
            % No contingency: a cue and a sync pulse on a fixed interval.
            p = teensy.Program(Name = "PassiveExposure", ...
                Description = "Stimulus presentation with a sync pulse and no response contingency.");
            p.Channels = teensy.Channel.defaultSet();

            teensy.Templates.addVars_(p, {
                "ITIDur",   5000, 100, 600000, "ms", "Interval between presentations."
                "StimDur",   500,  10,  60000, "ms", "Cue duration."
                "TrialType",   0,   0,      5, "",   "Recorded with each presentation."
                });

            p.addState(teensy.State("ITI", DurationMs = "@ITIDur", ...
                Notes = "Silent interval between presentations."));
            p.addState(teensy.State("Stimulus", DurationMs = "@StimDur", ...
                Notes = "Cue on, sync pulse out for alignment with the recording."));
            p.addState(teensy.State("Done", IsTerminal = true, ...
                RespCodeBits = [epsych.BitMask.CorrectReject, epsych.BitMask.TrialType_0], ...
                Notes = "Presentation complete. There is no response to score."));

            p.StartState = "ITI";

            p.States(1).Transitions(end+1) = teensy.Transition.to("Stimulus", ...
                teensy.Condition.timerElapsed());

            p.States(2).EntryActions(end+1) = teensy.Action.setOutput("HouseLight", 1);
            p.States(2).EntryActions(end+1) = teensy.Action.sync("Sync", 5);
            p.States(2).ExitActions(end+1) = teensy.Action.setOutput("HouseLight", 0);
            p.States(2).Transitions(end+1) = teensy.Transition.to("Done", ...
                teensy.Condition.timerElapsed());
        end

        function addTransition_(p, stateName, transition)
            % addTransition_(p, stateName, transition)
            % Append a transition to a state looked up by name.
            idx = p.stateIndex(stateName);
            p.States(idx).Transitions(end+1) = transition;
        end

        function addEntry_(p, stateName, action)
            % addEntry_(p, stateName, action)
            % Append an entry action to a state looked up by name.
            idx = p.stateIndex(stateName);
            p.States(idx).EntryActions(end+1) = action;
        end

        function addExit_(p, stateName, action)
            % addExit_(p, stateName, action)
            % Append an exit action to a state looked up by name.
            idx = p.stateIndex(stateName);
            p.States(idx).ExitActions(end+1) = action;
        end

        function addVars_(p, rows)
            % addVars_(p, rows)
            % Add variables from a {Name, Value, Min, Max, Units, Description} cell.
            for i = 1:size(rows, 1)
                p.addVariable(teensy.Variable(rows{i, 1}, ...
                    Value = rows{i, 2}, ...
                    Min = rows{i, 3}, ...
                    Max = rows{i, 4}, ...
                    Units = rows{i, 5}, ...
                    Description = rows{i, 6}));
            end
        end
    end
end
