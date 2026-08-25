classdef ComponentSpec
    % gui.ComponentSpec
    % Value object describing how a component is built into a
    % gui.BehaviorGUI and offered on the gui.BehaviorBuilder palette.
    %
    % A component declares one static method:
    %
    %   methods (Static)
    %       function s = getComponentSpec()
    %           s = gui.ComponentSpec();
    %           s.shape    = ["runtime","parent"];
    %           s.category = 'Displays';
    %       end
    %   end
    %
    % and gui.BehaviorGUI.add, the builder palette and the code generator
    % all read that one declaration. A class that declares NOTHING still
    % works: forClass infers a spec from the constructor signature, so a
    % component from outside this toolbox needs no registration at all.
    %
    % This mirrors hw.Interface.getCreationSpec / hw.InterfaceSpec, which
    % does the same job for hardware backends.
    %
    % SHAPE is the positional argument list, as tokens:
    %   parent          the container passed to add
    %   figure          the GUI's figure
    %   host            the gui.BehaviorGUI itself
    %   runtime         obj.RUNTIME
    %   psych           obj.Psych
    %   psychOrRuntime  obj.Psych when valid, else obj.RUNTIME
    %   keys            obj.Keys (gui.KeyBindings)
    %   canvas          the axes made per obj.canvas
    %   arg:Name        the named option Name, CONSUMED from the forwarded set
    %
    % Documentation: documentation/gui/gui_BehaviorGUI.md
    % See also gui.ComponentSpecOption, gui.BehaviorGUI.add

    properties
        % --- identity -------------------------------------------------
        className   (1,:) char = ''
        type        (1,:) char = ''   % stable id used by .eblt specs
        label       (1,:) char = ''
        category    (1,:) char = 'Displays'
        description (1,:) char = ''

        % --- construction ---------------------------------------------
        shape        (1,:) string = "parent"
        canvas       (1,:) char   = 'none'   % none|axes|uiaxes
        inject       (1,1) struct = struct() % OptionName -> token, only if unstated
        fixedOptions (1,1) struct = struct() % variant defaults; caller still wins
        hostOptions  (1,:) string = string.empty(1,0) % consumed here, never forwarded
        resolve         (1,:) string  = string.empty(1,0) % options -> resolveParameter_
        resolveRequired (1,1) logical = false
        singleton       (1,1) logical = false

        % --- preconditions --------------------------------------------
        requires        (1,:) string = string.empty(1,0) % psych | psychPlot
        psychTypes      (1,:) string = string.empty(1,0)
        requiredOptions (1,:) string = string.empty(1,0)

        % --- post-construction ----------------------------------------
        attachRuntime (1,1) logical = false
        start         (1,1) logical = false
        preFcn        = []   % opts = f(opts, guiObj, ctx); runs before construction
        postFcn       = []   % f(h, guiObj, ctx); ctx has .parent .canvas .options .host .spec

        % --- registration and keys ------------------------------------
        registerName   (1,:) char = ''
        keyBinding     (1,:) char = ''
        keyAction      = ''  % zero-arg method NAME on h, or f(h, guiObj)
        keyDescription (1,:) char = ''

        % --- options ---------------------------------------------------
        options (1,:) gui.ComponentSpecOption = gui.ComponentSpecOption.empty(1,0)

        % --- builder metadata ------------------------------------------
        placeable (1,1) logical = true
        poppable  (1,1) logical = false  % OR-ed with isa(cls,'gui.PopOut')
        emitClass (1,:) char = ''
    end

    properties (Dependent, SetAccess = private)
        needsPsych
        hasOptions
    end

    methods
        function obj = ComponentSpec(varargin)
            if nargin == 1 && (isstruct(varargin{1}) || isa(varargin{1},'gui.ComponentSpec'))
                obj = gui.ComponentSpec.fromStruct(varargin{1});
                return
            end
            if mod(nargin, 2) ~= 0
                error('gui:ComponentSpec:InvalidArguments', ...
                    'ComponentSpec expects name/value pairs or a single struct.');
            end
            for idx = 1:2:nargin
                obj.(varargin{idx}) = varargin{idx + 1};
            end
            obj = obj.normalized();
        end

        function tf = get.needsPsych(obj)
            tf = any(obj.requires == "psych" | obj.requires == "psychPlot");
        end

        function tf = get.hasOptions(obj)
            tf = ~isempty(obj.options);
        end

        function [v, has] = optionDefault(obj, name)
            % [v, has] = optionDefault(obj, name)
            % Declared default for one option. has=false means the component
            % has none, so add must omit the argument rather than invent one.
            v = []; has = false;
            if isempty(obj.options), return; end
            ix = strcmp({obj.options.name}, char(name));
            if ~any(ix), return; end
            o = obj.options(find(ix,1));
            v = o.defaultValue; has = o.hasDefault;
        end

        function tf = declaresOption(obj, name)
            tf = ~isempty(obj.options) && any(strcmp({obj.options.name}, char(name)));
        end

        function e = toCatalogEntry(obj)
            % e = toCatalogEntry(obj)
            % The struct gui.BehaviorBuilder.componentCatalog has always
            % returned, so every existing consumer keeps working unchanged.
            e = struct( ...
                'Type',        obj.type, ...
                'Display',     obj.label, ...
                'Category',    obj.category, ...
                'Description', obj.description, ...
                'NeedsPsych',  obj.needsPsych, ...
                'Poppable',    obj.poppable, ...
                'HasOptions',  obj.hasOptions, ...
                'EmitClass',   obj.emitClass);
            % Assigned after the struct call: struct('f',{{}}) makes an
            % empty ARRAY, the same trap componentCatalog documents.
            e.PsychTypes = cellstr(obj.psychTypes);
        end

        function obj = normalized(obj)
            obj.className      = char(string(obj.className));
            obj.type           = char(string(obj.type));
            obj.label          = char(string(obj.label));
            obj.category       = char(string(obj.category));
            obj.description    = char(string(obj.description));
            obj.canvas         = char(string(obj.canvas));
            obj.registerName   = char(string(obj.registerName));
            obj.keyBinding     = char(string(obj.keyBinding));
            obj.keyDescription = char(string(obj.keyDescription));
            obj.emitClass      = char(string(obj.emitClass));
            obj.options        = gui.ComponentSpecOption.normalizeArray(obj.options);
            if isempty(obj.canvas), obj.canvas = 'none'; end
            if isempty(obj.shape),  obj.shape  = "parent"; end
        end
    end

    methods (Static)
        function obj = fromStruct(s)
            if isa(s, 'gui.ComponentSpec'), obj = s.normalized(); return; end
            obj = gui.ComponentSpec();
            p = properties(obj);
            for idx = 1:numel(p)
                if isfield(s, p{idx})
                    try
                        obj.(p{idx}) = s.(p{idx});
                    catch
                    end
                end
            end
            obj = obj.normalized();
        end

        function obj = normalize(data)
            if isa(data, 'gui.ComponentSpec')
                obj = data.normalized();
            else
                obj = gui.ComponentSpec.fromStruct(data);
            end
        end

        function spec = forClass(cls, variant)
            % spec = forClass(cls)  |  forClass(cls, variant)
            % Build spec for a class named by its FULLY-QUALIFIED name. Never
            % throws: an unresolvable name yields a spec with an empty
            % className, which gui.BehaviorGUI.add reports at debug level.
            %
            % Memoized, because feval'ing a static getComponentSpec costs
            % ~0.5 ms against ~0.008 ms for the cache hit -- a 30-component
            % build pays 14 ms otherwise. Editing a getComponentSpec during a
            % session therefore has no effect until flushCache.
            arguments
                cls (1,:) char
                variant (1,:) char = ''
            end
            key = cls;
            if ~isempty(variant), key = [cls '#' variant]; end
            [hit, cached] = gui.ComponentSpec.cache_('get', key);
            if hit, spec = cached; return; end

            spec = gui.ComponentSpec();
            mc = [];
            try
                mc = meta.class.fromName(cls);
            catch ME
                % A class file with a syntax error throws here.
                vprintf(2, 'gui.ComponentSpec: cannot resolve "%s" (%s)', cls, ME.message)
            end
            if isempty(mc)
                spec = spec.normalized();
                gui.ComponentSpec.cache_("put", key, spec);
                return
            end

            if gui.ComponentSpec.declaresSpec_(mc)
                try
                    s = feval([cls '.getComponentSpec']);
                    spec = gui.ComponentSpec.pickVariant_(s, variant, cls);
                catch ME
                    vprintf(2, ['gui.ComponentSpec: %s.getComponentSpec failed (%s); ' ...
                        'inferring a spec from the constructor'], cls, ME.message)
                    spec = gui.ComponentSpec.infer_(mc);
                end
            else
                spec = gui.ComponentSpec.infer_(mc);
            end

            spec.className = cls;
            if isempty(spec.type),  spec.type  = gui.ComponentSpec.shortName_(cls);  end
            if isempty(spec.label), spec.label = gui.ComponentSpec.spacedName_(cls); end
            if isempty(spec.emitClass), spec.emitClass = cls; end
            if mc.Abstract
                spec.placeable = false;
            end
            spec.poppable = spec.poppable || ...
                gui.ComponentSpec.inheritsFrom_(mc, 'gui.PopOut');
            spec = spec.normalized();
            gui.ComponentSpec.cache_("put", key, spec);
        end

        function specs = packageSpecs(pkgName)
            % specs = packageSpecs("gui.components")
            % Every placeable component in a package, sorted by category then
            % label.
            %
            % NOT on gui.BehaviorGUI.add's path: the first .ClassList touch
            % parses every classdef in the package and costs ~1.1 s. This is
            % for the gui.BehaviorBuilder palette, which opens once.
            arguments
                pkgName (1,:) char
            end
            specs = gui.ComponentSpec.empty(1,0);
            p = [];
            try
                p = meta.package.fromName(pkgName);
            catch ME
                vprintf(2, 'gui.ComponentSpec: no package "%s" (%s)', pkgName, ME.message)
            end
            if isempty(p), return; end

            cl = p.ClassList;
            for i = 1:numel(cl)
                s = gui.ComponentSpec.forClass(cl(i).Name);
                if isempty(s.className) || ~s.placeable, continue; end
                specs(end+1) = s; %#ok<AGROW>
            end
            if isempty(specs), return; end
            [~, ix] = sortrows([string({specs.category}); string({specs.label})]');
            specs = specs(ix);
        end

        function flushCache()
            % flushCache()
            % Forget every memoized spec. Needed after editing a
            % getComponentSpec, which is otherwise invisible for the rest of
            % the session.
            gui.ComponentSpec.cache_("clear");
        end
    end

    methods (Static, Access = private)
        function varargout = cache_(action, key, value)
            % Memo behind one accessor, so flushCache can actually empty it.
            % A persistent inside forClass could only be cleared by clearing
            % the class, which is not something a running GUI should do.
            persistent M
            if isempty(M)
                M = containers.Map('KeyType','char','ValueType','any');
            end
            varargout = {};
            switch char(action)
                case 'get'
                    k = char(key);
                    hit = M.isKey(k);
                    varargout{1} = hit;
                    if nargout > 1
                        if hit
                            varargout{2} = M(k);
                        else
                            varargout{2} = [];
                        end
                    end
                case 'put'
                    M(char(key)) = value;
                case 'clear'
                    M = containers.Map('KeyType','char','ValueType','any');
                case 'count'
                    varargout{1} = M.Count;
            end
        end

        function tf = declaresSpec_(mc)
            % Does this class define a static getComponentSpec?
            tf = false;
            ml = mc.MethodList;
            if isempty(ml), return; end
            ix = strcmp({ml.Name}, 'getComponentSpec');
            tf = any(ix) && any([ml(ix).Static]);
        end

        function spec = pickVariant_(s, variant, cls)
            % One class may declare several variants (gui.Parameter_Control
            % is both the Control and the Button). Element 1 is the primary.
            s = gui.ComponentSpec.normalizeArrayLike_(s);
            if isempty(s)
                spec = gui.ComponentSpec();
                return
            end
            if isempty(variant)
                spec = s(1);
                return
            end
            ix = strcmpi({s.type}, variant);
            if ~any(ix)
                vprintf(2, ['gui.ComponentSpec: %s declares no variant "%s"; ' ...
                    'using the primary'], cls, variant)
                spec = s(1);
                return
            end
            spec = s(find(ix,1));
        end

        function a = normalizeArrayLike_(s)
            if isa(s, 'gui.ComponentSpec')
                a = s;
                for i = 1:numel(a), a(i) = a(i).normalized(); end
                return
            end
            a = gui.ComponentSpec.empty(1,0);
            for i = 1:numel(s)
                if iscell(s)
                    a(end+1) = gui.ComponentSpec.normalize(s{i}); %#ok<AGROW>
                else
                    a(end+1) = gui.ComponentSpec.normalize(s(i)); %#ok<AGROW>
                end
            end
        end

        function names = ctorArgs_(cls)
            % Constructor argument NAMES, read from the source file.
            %
            % Not from meta.method.InputNames: MATLAB collapses any function
            % whose arguments block declares name-value options down to
            % {'varargin'}, which is every component in this toolbox. The
            % source line is the only place the real names survive.
            names = {};
            try
                f = which(char(cls));
                if isempty(f) || ~isfile(f), return; end
                short = gui.ComponentSpec.shortName_(cls);
                txt = fileread(f);
                txt = regexprep(txt, '\.\.\.\s*\r?\n\s*', ' ');   % join continuations
                tok = regexp(txt, ...
                    ['function\s+[^=]*=\s*' short '\s*\(([^)]*)\)'], 'tokens', 'once');
                if isempty(tok), return; end
                names = strtrim(strsplit(tok{1}, ','));
                names = names(~cellfun(@isempty, names));
            catch ME
                vprintf(3, 'gui.ComponentSpec: could not read %s constructor (%s)', ...
                    cls, ME.message)
            end
        end

        function spec = infer_(mc)
            % Spec inferred from the constructor's argument NAMES, so a
            % component that declares nothing still builds. Reported at trace
            % level, since a wrong guess shows up as a constructor failure.
            spec = gui.ComponentSpec();
            names = gui.ComponentSpec.ctorArgs_(mc.Name);
            if isempty(names), return; end

            tok = string.empty(1,0);
            seenSource = false;
            for i = 1:numel(names)
                n = char(names{i});
                if any(strcmpi(n, {'options','opts','varargin','nvargs','args'}))
                    break
                end
                switch lower(n)
                    case {'runtime','rt'}
                        tok(end+1) = "runtime"; %#ok<AGROW>
                        seenSource = true;
                    case {'pobj','psychobj'}
                        tok(end+1) = "psych"; %#ok<AGROW>
                        seenSource = true;
                    case {'source','src'}
                        % Only a LEADING source names the data object; a
                        % later one is the component's own (gui.OnlinePlot's
                        % source is a trace list, not a runtime).
                        if seenSource
                            tok(end+1) = "arg:" + string(n); %#ok<AGROW>
                        else
                            tok(end+1) = "psychOrRuntime"; %#ok<AGROW>
                            seenSource = true;
                        end
                    case {'parentgui','guiobj'}
                        tok(end+1) = "host"; %#ok<AGROW>
                    case {'fig','hfig','figure'}
                        tok(end+1) = "figure"; %#ok<AGROW>
                    case {'parent','container','hparent'}
                        tok(end+1) = "parent"; %#ok<AGROW>
                    case {'ax','hax','axes','haxes'}
                        tok(end+1) = "canvas"; %#ok<AGROW>
                        spec.canvas = 'axes';
                    otherwise
                        tok(end+1) = "arg:" + string(n); %#ok<AGROW>
                end
            end
            if isempty(tok), tok = "parent"; end
            spec.shape = tok;
            vprintf(3, 'gui.ComponentSpec: inferred shape [%s] for %s', ...
                strjoin(cellstr(tok), ' '), mc.Name)
        end

        function tf = inheritsFrom_(mc, targetName)
            % Depth-first walk of the meta.class superclass tree.
            % superclasses() omits Hidden ancestors, which would make a
            % future Hidden intermediate silently defeat this test -- the
            % same trap helpers/isConcreteStimType.m documents.
            tf = false;
            if isempty(mc), return; end
            if strcmp(mc.Name, targetName), tf = true; return; end
            for k = 1:numel(mc.SuperclassList)
                if gui.ComponentSpec.inheritsFrom_(mc.SuperclassList(k), targetName)
                    tf = true;
                    return
                end
            end
        end

        function n = shortName_(cls)
            parts = strsplit(char(cls), '.');
            n = parts{end};
        end

        function n = spacedName_(cls)
            n = gui.ComponentSpec.shortName_(cls);
            n = strrep(n, '_', ' ');
            n = regexprep(n, '([a-z0-9])([A-Z])', '$1 $2');
        end
    end
end
