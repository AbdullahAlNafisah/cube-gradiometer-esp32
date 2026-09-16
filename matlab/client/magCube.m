function magCube(h)
%MAGCUBE  Live 3D view of the cube with each face's field vector.
%
%   magCube        open the board, show the cube, close it again on Stop
%   magCube(h)     use a handle from magOpen, and leave it open
%
%   Arrows start at each face centre and point along that sensor's field,
%   rotated into world axes (X=East, Y=North, Z=Up). "Field" shows the full
%   vector; "Deviation" subtracts the four-sensor mean, leaving the differential
%   part the gradient is computed from.
%
%   See also MAGOPEN, MAGFIELD, MAGROT.

WINDOW = 25;

owned = nargin < 1;
if owned, h = magOpen; end

names = h.names;
nS    = numel(names);
cols  = lines(nS);
a     = 0.015;

fig = figure('Name', 'Magnetic field cube', 'NumberTitle', 'off', ...
             'Color', 'w', 'Position', [60 60 1180 700]);
setappdata(fig, 'running', true);
setappdata(fig, 'mode', 'field');

uicontrol(fig, 'Style', 'pushbutton', 'String', 'Stop', ...
          'FontSize', 12, 'FontWeight', 'bold', 'Units', 'normalized', ...
          'Position', [0.28 0.02 0.09 0.05], ...
          'Callback', @(~,~) setappdata(fig, 'running', false));
btn = uicontrol(fig, 'Style', 'pushbutton', 'String', 'Show: Field', ...
          'FontSize', 11, 'Units', 'normalized', 'Position', [0.40 0.02 0.16 0.05]);
btn.Callback = @(s,~) toggleMode(fig, s);

ax = axes(fig, 'Position', [0.02 0.10 0.62 0.86]);
hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on'); axis(ax, 'equal');
view(ax, -37, 20);
xlabel(ax, 'East (m)'); ylabel(ax, 'North (m)'); zlabel(ax, 'Up (m)');

drawCube(ax, a, names, cols);

arrows = gobjects(nS, 1);
for k = 1:nS
    arrows(k) = quiver3(ax, 0, 0, 0, 0, 0, 0, 0, 'LineWidth', 2.5, ...
                        'Color', cols(k,:), 'MaxHeadSize', 1e3, ...
                        'AutoScale', 'off', 'Alignment', 'tail');
end
meanArrow = quiver3(ax, 0, 0, 0, 0, 0, 0, 0, 'LineWidth', 2, 'Color', [0.35 0.35 0.35], ...
                    'MaxHeadSize', 1e3, 'AutoScale', 'off', 'LineStyle', '--');

lim = a * 2.05;
xlim(ax, [-lim lim]); ylim(ax, [-lim lim]); zlim(ax, [-lim lim]);
set(ax, 'BoxStyle', 'back');

panel = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
                  'Position', [0.66 0.10 0.32 0.86], ...
                  'HorizontalAlignment', 'left', 'BackgroundColor', 'w', ...
                  'FontName', 'monospaced', 'FontSize', 11);

try
    while ishandle(fig) && getappdata(fig, 'running')
        F = magField(magRead(h, WINDOW), names);
        useDev = strcmp(getappdata(fig, 'mode'), 'dev');
        V = F.B; if useDev, V = F.dev; end

        m = max(vecnorm(V, 2, 2));
        if ~isfinite(m) || m <= 0, m = 1; end
        sc = (a * 1.15) / m;
        for k = 1:nS
            set(arrows(k), 'XData', F.pos(k,1), 'YData', F.pos(k,2), 'ZData', F.pos(k,3), ...
                           'UData', V(k,1)*sc, 'VData', V(k,2)*sc, 'WData', V(k,3)*sc);
        end
        if useDev
            set(meanArrow, 'UData', 0, 'VData', 0, 'WData', 0);
        else
            set(meanArrow, 'UData', F.mean(1)*sc, 'VData', F.mean(2)*sc, 'WData', F.mean(3)*sc);
        end
        title(ax, sprintf('%s   \\bullet  longest arrow = %.1f \\muT', ...
                          ternary(useDev, 'deviation from mean', 'field'), m));
        set(panel, 'String', report(F));
        drawnow limitrate
    end
catch err
    if owned, magClose(h); end
    if ishandle(fig), close(fig); end
    rethrow(err);
end

if ishandle(fig), close(fig); end
if owned, magClose(h); end
end

% ---------------------------------------------------------------------------------
function toggleMode(fig, src)
if strcmp(getappdata(fig, 'mode'), 'field')
    setappdata(fig, 'mode', 'dev');  src.String = 'Show: Deviation';
else
    setappdata(fig, 'mode', 'field'); src.String = 'Show: Field';
end
end

% ---------------------------------------------------------------------------------
function drawCube(ax, a, names, cols)
%DRAWCUBE  Wireframe cube with the four instrumented side faces shaded.
c = [-a -a -a; a -a -a; a a -a; -a a -a; -a -a a; a -a a; a a a; -a a a];
E = [1 2;2 3;3 4;4 1; 5 6;6 7;7 8;8 5; 1 5;2 6;3 7;4 8];
for i = 1:size(E,1)
    plot3(ax, c(E(i,:),1), c(E(i,:),2), c(E(i,:),3), 'k-', 'LineWidth', 1);
end
faces = [2 3 7 6; 3 4 8 7; 4 1 5 8; 1 2 6 5];   % East, North, West, South
for k = 1:min(numel(names), 4)
    patch(ax, 'Vertices', c, 'Faces', faces(k,:), 'FaceColor', cols(k,:), ...
          'FaceAlpha', 0.13, 'EdgeColor', 'none');
    p = a * [cosd((k-1)*90), sind((k-1)*90), 0];
    plot3(ax, p(1), p(2), p(3), 'o', 'MarkerSize', 7, 'MarkerFaceColor', cols(k,:), ...
          'MarkerEdgeColor', 'w', 'LineWidth', 1);
    text(ax, p(1)*1.8, p(2)*1.8, -a*0.85, names(k), 'Color', cols(k,:), ...
         'FontWeight', 'bold', 'FontSize', 11, 'HorizontalAlignment', 'center');
end
end

% ---------------------------------------------------------------------------------
function s = report(F)
s = sprintf('world frame  X=East  Y=North  Z=Up\n\n');
s = [s sprintf('%-6s %7s %7s %7s %7s\n', 'face', 'Bx', 'By', 'Bz', '|B|')];
for k = 1:numel(F.names)
    s = [s sprintf('%-6s %7.2f %7.2f %7.2f %7.2f\n', F.names(k), F.B(k,:), norm(F.B(k,:)))]; %#ok<AGROW>
end
s = [s sprintf('\nmean   %7.2f %7.2f %7.2f %7.2f uT\n', F.mean, norm(F.mean))];
s = [s sprintf('spread %7.2f uT\n', max(vecnorm(F.B,2,2)) - min(vecnorm(F.B,2,2)))];
s = [s sprintf('\ngradient over %.0f cm (uT/m)\n', F.cube*100)];
s = [s sprintf('dB/dx  %8.1f %8.1f %8.1f\n', F.gradX)];
s = [s sprintf('dB/dy  %8.1f %8.1f %8.1f\n', F.gradY)];
end

% ---------------------------------------------------------------------------------
function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
