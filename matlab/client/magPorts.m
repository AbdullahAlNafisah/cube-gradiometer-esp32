function p = magPorts()
%MAGPORTS  Serial ports the board could be on.
%
%   Windows lists every COM port. Elsewhere the legacy /dev/ttyS* are dropped:
%   they are never USB adapters, and probing all 32 of them is a long wait for
%   a guaranteed failure.

a = string(serialportlist("available"));
if isempty(a), p = strings(0,1); return, end

if ispc
    p = a;
else
    p = a(contains(a, "ttyUSB") | contains(a, "ttyACM") | contains(a, "usbserial") | ...
          contains(a, "usbmodem") | contains(a, "SLAB") | contains(a, "wchusb"));
end
p = p(:);
end
