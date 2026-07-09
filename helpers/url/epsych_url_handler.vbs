' epsych_url_handler.vbs
'
' OS handler for the "epsych://" URL protocol used by EPsych v2.
'
' Registered (via epsych.RunExpt.registerURLProtocol) so that clicking an
' epsych:// link -- e.g. from a subject's data-log Google Sheet -- forwards
' the URL to a running MATLAB / RunExpt session through the MATLAB Automation
' Server (COM). All URL parsing happens in MATLAB
' (epsych.RunExpt.handleConfigLink); this script only relays the raw URL.
'
' Invoked as:  wscript.exe "epsych_url_handler.vbs" "<the full epsych:// url>"

Option Explicit

Dim args, url, ml

Set args = WScript.Arguments
If args.Count = 0 Then WScript.Quit

url = args(0)

' Connect to the already-running MATLAB automation server. RunExpt enables it
' on startup via enableservice('AutomationServer', true).
On Error Resume Next
Set ml = GetObject(, "Matlab.Application")
If Err.Number <> 0 Or ml Is Nothing Then
    MsgBox "EPsych is not running." & vbCrLf & vbCrLf & _
           "Open RunExpt in MATLAB, then click the link again.", _
           vbExclamation, "EPsych"
    WScript.Quit
End If
On Error Goto 0

' Escape single quotes so the URL is a valid single-quoted MATLAB string.
ml.Execute "epsych.RunExpt.handleConfigLink('" & Replace(url, "'", "''") & "')"
