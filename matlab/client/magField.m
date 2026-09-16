function F = magField(S, names)
%MAGFIELD  World-frame field per face, and the gradient between opposite faces.
%
%   F = magField(S)          S from magRead
%   F = magField(S, names)   sensor names, default East/North/West/South
%
%   F.B      4x3 world-frame field per face (uT), averaged over the samples
%   F.pos    4x3 face-centre positions (m)
%   F.mean   1x3 common-mode field (uT)
%   F.dev    4x3 B minus the common mode, the part that carries the gradient
%   F.gradX  1x3 dB/dx from East minus West (uT/m)
%   F.gradY  1x3 dB/dy from North minus South (uT/m)
%
%   See also MAGROT, MAGCUBE.

if nargin < 2 || isempty(names), names = ["East" "North" "West" "South"]; end
AZ   = [0 90 180 270];
CUBE = 0.03;
a    = CUBE/2;

n = numel(names);
B = zeros(n,3); P = zeros(n,3);
for k = 1:n
    b = [mean(S.(char(names(k)+"_x_uT")), 'omitnan'), ...
         mean(S.(char(names(k)+"_y_uT")), 'omitnan'), ...
         mean(S.(char(names(k)+"_z_uT")), 'omitnan')];
    B(k,:) = (magRot(AZ(k)) * b.').';
    P(k,:) = a * [cosd(AZ(k)), sind(AZ(k)), 0];
end

F.names = names;
F.az    = AZ;
F.cube  = CUBE;
F.pos   = P;
F.B     = B;
F.mean  = mean(B, 1, 'omitnan');
F.dev   = B - F.mean;
F.gradX = (B(1,:) - B(3,:)) / CUBE;
F.gradY = (B(2,:) - B(4,:)) / CUBE;
end
