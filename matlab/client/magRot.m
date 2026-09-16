function R = magRot(azDeg)
%MAGROT  Sensor body axes to world axes, for a board on the face facing azDeg.
%
%   World is X=East, Y=North, Z=Up. azDeg is the outward face normal, measured
%   counterclockwise from East.
%
%   Mounting: component side outward, pin header at the bottom. The silkscreen
%   marks +X up the board and +Y to the right; right-handedness then forces +Z
%   into the board. So on the cube: +X is world up, +Y is right seen from
%   outside, +Z points inward through the face.
%
%   Columns of R are where the sensor's own X, Y, Z land in world coordinates.

th = deg2rad(azDeg);
R = [0, -sin(th), -cos(th);
     0,  cos(th), -sin(th);
     1,  0,        0      ];
end
