classdef FakeSubjectRegistry < epsych.SubjectRegistry
    % FakeSubjectRegistry
    % A test double for epsych.SubjectRegistry: records every call, answers
    % subjectStatus from a table the test sets, and throws from every call
    % when Throw is set -- which is how a test proves a broken adapter costs a
    % log line and never a roster write or a session.
    %
    %   F = FakeSubjectRegistry();
    %   epsych.SubjectRegistry.current(Use=F);
    %   ... exercise EPsych ...
    %   epsych.SubjectRegistry.current(Reset=true);
    %
    % See also: tmp/smoke_test_subject_registry.m, epsych.SubjectRegistry

    properties
        Running = logical.empty(1, 0)
        Sessions = {}
        Weights = struct('Name', {}, 'RegistryID', {}, 'SubjectID', {}, 'Grams', {}, 'When', {})
        Status table = epsych.SubjectRegistry.emptyStatus()
        Subjects table = epsych.SubjectRegistry.emptySubjects()
        ProjectsTable table = epsych.SubjectRegistry.emptyProjects()
        Filters = {}            % every findSubjects filter, in order
        Refreshed = {}          % every refreshStatus id list, in order
        SettingsOpened (1,1) double = 0
        Throw (1,1) logical = false
    end

    methods
        function T = findSubjects(obj, filter)
            obj.check_();
            obj.Filters{end+1} = filter;
            T = obj.Subjects;
            if isstruct(filter) && isfield(filter, 'Project') && strlength(filter.Project) > 0
                T = T(T.ProjectRegistryID == filter.Project, :);
            end
        end

        function T = projects(obj)
            obj.check_();
            T = obj.ProjectsTable;
        end

        function rep = refreshStatus(obj, ids)
            obj.check_();
            obj.Refreshed{end+1} = ids;
            rep = struct('OK', true, 'Message', sprintf("Read %d subject(s).", numel(ids)));
        end

        function openSettings(obj)
            obj.SettingsOpened = obj.SettingsOpened + 1;
        end

        function tf = isEnabled(~)
            tf = true;
        end

        function s = label(~)
            s = "Fake DB";
        end

        function st = status(obj)
            obj.check_();
            st = epsych.SubjectRegistry.blankStatus();
            st.State = "connected";
            st.Pending = numel(obj.Sessions) + numel(obj.Weights);
        end

        function sessionRunning(obj, tf)
            obj.check_();
            obj.Running(end+1) = tf;
        end

        function sessionSaved(obj, records)
            obj.check_();
            obj.Sessions{end+1} = records;
        end

        function weightMeasured(obj, subject, grams, when)
            obj.check_();
            obj.Weights(end+1) = struct('Name', string(subject.Name), ...
                'RegistryID', string(subject.RegistryID), 'SubjectID', string(subject.SubjectID), ...
                'Grams', grams, 'When', when);
        end

        function T = subjectStatus(obj, registryIds)
            obj.check_();
            T = epsych.SubjectRegistry.emptyStatus(registryIds);
            for k = 1:height(T)
                hit = find(obj.Status.RegistryID == T.RegistryID(k), 1);
                if ~isempty(hit)
                    T(k, :) = obj.Status(hit, :);
                end
            end
        end
    end

    methods (Access = private)
        function check_(obj)
            if obj.Throw
                error('FakeSubjectRegistry:Broken', 'The fake registry was told to fail.');
            end
        end
    end
end
