function originalState = AlwaysOnTop(self, ontop)
% AlwaysOnTop — Toggle the main window "always on top" setting.
% Inputs
%   ontop (logical) — Optional; when omitted, flips current state.
arguments
    self
    ontop (1,1) logical = false
end
originalState = isequal(self.H.figure1.WindowStyle,'alwaysontop');
if nargin < 2
    ontop = ~originalState;
end

% The menu item's Checked state and the toolbar toggle's State both follow
% the actual window state, whichever entry point flipped the setting.
if ontop
    set(self.H.always_on_top,'Checked','on');
    set(self.H.tb_always_on_top,'State','on');
    set(self.H.figure1,'WindowStyle','alwaysontop');
else
    set(self.H.always_on_top,'Checked','off');
    set(self.H.tb_always_on_top,'State','off');
    set(self.H.figure1,'WindowStyle','normal');
end

if nargout == 0
    clear ontop
end
