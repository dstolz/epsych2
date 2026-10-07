classdef Export
    % behavior.Export  Tidy tables of an analysis, written for other software.
    %
    % Every row an export carries comes from ONE table, the one
    % behavior.Aggregate.thresholds builds, plus the per-result detail the
    % results themselves hold (fit, session metrics, reversals):
    %
    %   T    = behavior.Aggregate.thresholds(results, catalog.Sessions);
    %   Tbls = behavior.Export.tables(T, results, Subjects = catalog.Subjects);
    %   files = behavior.Export.write(Tbls, folder, Formats = ["csv" "xlsx"]);
    %
    % SCHEMA IS THE SINGLE SOURCE OF TRUTH. schema() names every column of
    % every table, in order, with its type, unit and meaning; tables() builds
    % FROM it, so a column the schema does not list is not produced and one it
    % lists is always present (empty text, NaN, false or NaT when the source
    % lacks it). Two column families are dynamic and appear in the schema as
    % placeholders: tag_<k> (one per tag position any session has, at least
    % tag_1) and group_<name> (one per manual grouping the table carries).
    % dictionary(Tbls) expands them for the columns actually present and is
    % what write() saves as <prefix>columns.csv.
    %
    % FILE RULES. CSV is UTF-8 with a header, one file per table; logicals are
    % TRUE/FALSE, datetimes ISO 8601 (yyyy-MM-dd'T'HH:mm:ss), numbers carry 10
    % significant digits, and a number that is not finite is an EMPTY field --
    % a missing measurement is never written as a word a reader could mistake
    % for a value, and an infinity is never written at all. XLSX is one
    % workbook with a sheet per table, MAT one struct EPsychExport.
    %
    % Static only, headless, touches no preference.
    %
    % See also: behavior.Aggregate, behavior.Catalog, behavior.Session.analyze

    properties (Constant)
        % Every table tables() can build, in the order it builds them.
        TABLES = ["sessions" "subjects" "thresholds" "fits" "metrics" "reversals" "notes"]
        % Largest row count an Excel sheet takes (header excluded).
        MAX_XLSX_ROWS = 1048575
        % ISO 8601 text of a datetime in every text export.
        TIME_FORMAT = "yyyy-MM-dd'T'HH:mm:ss"
    end

    methods (Static)
        Tbls = tables(T, results, options)
        files = write(Tbls, folder, options)
        S = schema()
        D = dictionary(Tbls)
        txt = toTSV(T)
        tf = copyTable(T)
    end
end
