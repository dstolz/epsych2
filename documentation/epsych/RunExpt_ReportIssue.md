# Report an Issue

**Help → Report an Issue on GitHub...** in the RunExpt session window composes a bug report
out of what EPsych already knows — version, commit, host, session state, and the tail of the
day's error log — shows it to you, and then opens GitHub's bug-report form with those sections
already filled in.

Implemented by [`epsych.RunExpt.ReportIssue`](../../obj/+epsych/@RunExpt/ReportIssue.m), with
the report gathered by
[`issueReportFields`](../../obj/+epsych/@RunExpt/issueReportFields.m) and the link built by
[`issueURL`](../../obj/+epsych/@RunExpt/issueURL.m). The form itself is
[`.github/ISSUE_TEMPLATE/bug_report.yml`](../../.github/ISSUE_TEMPLATE/bug_report.yml).

## What travels, and how

The report is **text in a URL**. GitHub's issue forms are prefilled by query parameters named
for the field ids in the template, so nothing is uploaded from MATLAB, no credentials are
involved, and the report is still on your screen — and still editable — until you submit the
form in the browser.

That mechanism is also the constraint:

- **A link cannot attach a file.** An attachment needs an authenticated upload, which is why
  the full log is offered on the clipboard and revealed in the file browser instead.
- **A URL has a length limit.** Over-long ones are answered with `414`, so `issueURL` keeps the
  whole link under 6000 characters, trimming the excerpt **from its start** — the end of a log
  is the part describing the failure — and saying in the excerpt how many lines it dropped. A
  log line encodes to roughly two and a half times its length, so in practice 40–50 lines fit.
  The dialog reports the link size and what will not fit as you edit.

## The review step

The preview is the point of the feature, not a confirmation prompt. An EPsych log names
subjects, protocol files, and data paths; the tracker is public; and only the operator can say
which of those may be published. So:

- Both sections are shown in editable text boxes. Delete anything that should not be published.
- **Include this error log excerpt** drops the excerpt entirely without clearing it, so
  unticking is reversible.
- Nothing opens, and nothing reaches the clipboard, until **Open Issue**.

## What is in the Environment block

From `EPsychInfo`: EPsych version and data format, commit and its timestamp, latest tag, the
`obj/stimgen` submodule commit, and — only when this checkout is one — the worktree name. From
`EPsychInfo.diagnostics`: MATLAB version and release, platform, hostname, memory, and installed
toolboxes.

From the session: `STATE`, how many subjects are configured, subject 1's
protocol **file name** (not its path, whose folders are usually a subject name), each interface's
class and whether it is currently connected, and every `FUNCS` field. Each value is fetched
inside its own `try` — several backends' `IsConnected` getters talk to the device, and a rig
whose hardware just failed is exactly when this runs — so a failure costs one line of the report
rather than the report.

## The log excerpt

`issueReportFields` flushes the logger first (the file sink buffers, so without it the excerpt
would end several messages before the failure) and takes the last 120 lines of
`eplog.Logger.instance().LogFile`. The dialog header names the file and says how much of it the
excerpt covers. When file logging is disabled for the session there is no excerpt: the section
is disabled and says so, and the report goes without it.

Two checkboxes cover the part that does not fit in a link:

- **Copy the full log to the clipboard** — paste it into the issue body.
- **Show the log file so I can attach it** — opens the containing folder with the file selected
  (`explorer /select` on Windows, `open -R` on macOS), ready to drag onto the issue. This is the
  only route to a real attachment.

## Using it from a script

`issueReportFields` is public and headless, so a report can be composed without the dialog:

```matlab
rx = epsych.RunExpt;
fields = rx.issueReportFields(MaxLogLines=200);
disp(fields.environment)

[url, dropped] = epsych.RunExpt.issueURL(fields);
fprintf('%d characters, %d excerpt line(s) dropped\n', numel(url), dropped);
```

`issueURL` takes a `MaxLength` option for a different budget, and reads only the `environment`
and `logs` fields, so edited text can be passed straight back in.

## Requesting a feature

**Help → Request a Feature on GitHub...** opens
[`feature_request.yml`](../../.github/ISSUE_TEMPLATE/feature_request.yml) in the browser
straight away. There is no preview because there is nothing to review: the only thing prefilled
is a **Version** line — EPsych version, commit, and MATLAB release — and none of the session's
config paths, subject names, or log lines travel with it. The commit is worth carrying anyway,
since a request is sometimes already answered further along `master`.

The form asks for the experiment behind the request before the control the requester has in
mind, and points stimulus-generation requests at
[dstolz/stimgen](https://github.com/dstolz/stimgen/issues), whose code is a pinned submodule
here rather than part of this repository.

Implemented by [`RequestFeature`](../../obj/+epsych/@RunExpt/RequestFeature.m); both forms share
`epsych.RunExpt.encodeQueryValue`, which encodes a space as `%20` rather than `urlencode`'s `+`
— only `%20` survives a reader that decodes with `decodeURIComponent`.

## Checks

`tmp/smoke_test_report_issue.m` covers the URL shape and encoding, the trim-to-fit rule
(including a budget nothing fits in), the gathered report, the dialog's structure, and that both
Help menu items are wired. It never presses **Open Issue** and never calls `RequestFeature` —
both open a browser on a public tracker.

## See also

- [RunExpt_GUI_Overview.md](../overviews/RunExpt_GUI_Overview.md) — the Help menu in context
- [eplog_Logging.md](../eplog/eplog_Logging.md) — where the log comes from and how to change its
  level or location
