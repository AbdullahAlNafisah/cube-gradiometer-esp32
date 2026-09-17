function magCubeFigure(outFile)
%MAGCUBEFIGURE  The cube with one field vector per side face, for the README.
%
%   magCubeFigure              write docs/cube.png next to the repo's docs
%   magCubeFigure("out.png")   write somewhere else
%
%   A still of what MAGCUBE shows live. Needs no hardware: the field drawn here
%   is a uniform part plus a symmetric, traceless gradient, so the four faces
%   read visibly different vectors the way they would over a real source.
%
%   Face order, azimuths and positions match MAGFIELD. World axes are
%   X=East, Y=North, Z=Up.
%
%   See also MAGCUBE, MAGFIELD.

CUBE  = 0.03;                 % m, cube edge
a     = CUBE / 2;
AZ    = [0 90 180 270];       % outward face normals, ccw from East
names = ["East" "North" "West" "South"];

P = a * [cosd(AZ).', sind(AZ).', zeros(4,1)];      % face centres, m

B0 = [12 26 -38];                                  % uT, roughly Earth-sized
G  = [300 120 0; 120 -200 0; 0 0 -100];            % uT/m, symmetric, trace 0
B  = B0 + (G * P.').';                             % uT at each face centre

INK = [0.54 0.56 0.60]; ORANGE = [0.85 0.55 0.17]; BLUE = [0.29 0.56 0.85];
col = [ORANGE; BLUE; ORANGE; BLUE];                % E/W on x, N/S on y

fig = figure('Color', 'w', 'Position', [100 100 780 620], 'Visible', 'off', ...
             'InvertHardcopy', 'off');
ax  = axes(fig); hold(ax, 'on');

% the cube
V = a * [-1 -1 -1; 1 -1 -1; 1 1 -1; -1 1 -1; -1 -1 1; 1 -1 1; 1 1 1; -1 1 1];
F = [1 2 3 4; 5 6 7 8; 1 2 6 5; 2 3 7 6; 3 4 8 7; 4 1 5 8];
patch(ax, 'Vertices', V, 'Faces', F, 'FaceColor', [0.93 0.94 0.95], ...
      'FaceAlpha', 0.25, 'EdgeColor', INK, 'LineWidth', 1.2);

% one arrow per side face, all to the same scale
sc = 1.3 * a / max(vecnorm(B, 2, 2));
for k = 1:4
    quiver3(ax, P(k,1), P(k,2), P(k,3), B(k,1)*sc, B(k,2)*sc, B(k,3)*sc, 0, ...
            'Color', col(k,:), 'LineWidth', 2.5, 'MaxHeadSize', 0.6);
    plot3(ax, P(k,1), P(k,2), P(k,3), 'o', 'MarkerSize', 6, ...
          'MarkerFaceColor', col(k,:), 'MarkerEdgeColor', 'none');
    lp = P(k,:) * 1.75;
    text(ax, lp(1), lp(2), lp(3), names(k), 'Color', col(k,:), ...
         'FontWeight', 'bold', 'FontSize', 12, 'HorizontalAlignment', 'center');
end

axis(ax, 'equal'); grid(ax, 'on'); box(ax, 'off');
view(ax, -37.5, 22);
set(ax, 'XColor', INK, 'YColor', INK, 'ZColor', INK, 'GridAlpha', 0.15, ...
        'Color', 'w', 'GridColor', INK);   % R2026 defaults to a dark theme
xlabel(ax, 'East (m)'); ylabel(ax, 'North (m)'); zlabel(ax, 'Up (m)');
title(ax, sprintf('%g cm cube, one magnetometer per side face', CUBE*100), ...
      'Color', INK, 'FontWeight', 'normal');

if nargin < 1 || strlength(string(outFile)) == 0
    here    = fileparts(mfilename('fullpath'));          % matlab/analysis
    outFile = fullfile(here, '..', '..', 'docs', 'cube.png');
end
exportgraphics(fig, char(outFile), 'Resolution', 150, 'BackgroundColor', 'white');
close(fig);
fprintf('wrote %s\n', char(outFile));
end
