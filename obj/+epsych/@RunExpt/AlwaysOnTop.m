function originalState = AlwaysOnTop(self, ontop)
% AlwaysOnTop — Toggle the main window "always on top" setting.
% Inputs
%   ontop (logical) — Optional; when omitted, flips current state.
arguments
    self (1,1) ep_RunExpt2
    ontop (1,1) logical = false
end
originalState = isequal(self.H.figure1.WindowStyle,'alwaysontop');
if nargin < 2
    ontop = ~originalState;
end

if ontop
    set(self.H.always_on_top,'Checked','on');
    set(self.H.figure1,'WindowStyle','alwaysontop');
else
    set(self.H.always_on_top,'Checked','off');
    set(self.H.figure1,'WindowStyle','normal');
end

if nargout == 0
    clear ontop
end
