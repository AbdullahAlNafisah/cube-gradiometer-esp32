function magLive(h)
%MAGLIVE  Plot every axis of every sensor live until you press Stop.
%
%   magLive        open the board, plot, close it again when you stop
%   magLive(h)     use a handle from magOpen, and leave it open
%
%   One column per sensor, one row per axis: X on top, then Y, then Z. Each row
%   shares a y-axis across all four sensors, so the same component can be
%   compared face to face directly.
%
%   Press the Stop button, or just close the window.
%
%   See also MAGOPEN, MAGREAD, MAGCLOSE.

WINDOW = 250;                      % samples kept on screen (~10 s at 25 Hz)
CHUNK  = 5;                        % samples pulled per refresh
AXES   = ["x" "y" "z"];

owned = nargin < 1;
if owned, h = magOpen; end

names = h.names;
nS    = numel(names);
nA    = numel(AXES);
cols  = lines(nS);

fig = figure('Name', 'Magnetometer array - live', 'NumberTitle', 'off', ...
             'Color', 'w', 'Position', [60 60 1280 720]);
setappdata(fig, 'running', true);
uicontrol(fig, 'Style', 'pushbutton', 'String', 'Stop', ...
          'FontSize', 12, 'FontWeight', 'bold', ...
          'Units', 'normalized', 'Position', [0.46 0.015 0.08 0.05], ...
          'Callback', @(~,~) setappdata(fig, 'running', false));

% Explicit positions rather than subplot, to leave room for the button.
L = 0.055; R = 0.99; B = 0.115; T = 0.93; hgap = 0.022; vgap = 0.055;
w  = (R - L - (nS-1)*hgap) / nS;
hh = (T - B - (nA-1)*vgap) / nA;

ax = gobjects(nA, nS);
tr = gobjects(nA, nS);
tx = gobjects(nA, nS);
for r = 1:nA
    for c = 1:nS
        pos = [L + (c-1)*(w+hgap), T - r*hh - (r-1)*vgap, w, hh];
        ax(r,c) = axes(fig, 'Position', pos);
        hold(ax(r,c), 'on'); grid(ax(r,c), 'on'); box(ax(r,c), 'on');
        tr(r,c) = plot(ax(r,c), nan, nan, 'LineWidth', 1.2, 'Color', cols(c,:));
        tx(r,c) = text(ax(r,c), 0.03, 0.90, '', 'Units', 'normalized', ...
                       'FontWeight', 'bold', 'FontSize', 9, ...
                       'BackgroundColor', [1 1 1 0.6]);
        if r == 1
            title(ax(r,c), names(c), 'FontSize', 12, 'Color', cols(c,:));
        end
        if c == 1
            ylabel(ax(r,c), sprintf('B_%s  (\\muT)', AXES(r)), 'FontSize', 11);
        else
            set(ax(r,c), 'YTickLabel', []);
        end
        if r == nA
            xlabel(ax(r,c), 'time (s)');
        else
            set(ax(r,c), 'XTickLabel', []);
        end
    end
end

buf = [];
try
    while ishandle(fig) && getappdata(fig, 'running')
        if h.mode == "stream"
            % The capture file already holds the history, so take the whole
            % window each frame. Appending small chunks instead would skip
            % everything that arrived while the previous frame was drawing.
            buf = magRead(h, WINDOW);
        else
            % serialport consumes the stream in order, so chunks join up with
            % no gaps; anything not yet read is waiting in the OS buffer.
            buf = [buf; magRead(h, CHUNK)]; %#ok<AGROW>
            if height(buf) > WINDOW, buf = buf(end-WINDOW+1:end, :); end
        end
        if isempty(buf), continue, end

        t = (buf.t_ms - buf.t_ms(1)) / 1000;
        for r = 1:nA
            lo = inf; hi = -inf;
            for c = 1:nS
                y = buf.(char(names(c) + "_" + AXES(r) + "_uT"));
                set(tr(r,c), 'XData', t, 'YData', y);
                set(tx(r,c), 'String', sprintf('%+.2f', y(end)));
                lo = min(lo, min(y)); hi = max(hi, max(y));
            end
            if isfinite(lo) && isfinite(hi)
                pad = max((hi - lo) * 0.12, 0.5);      % shared scale per row
                set(ax(r,:), 'YLim', [lo-pad, hi+pad]);
            end
        end
        if t(end) > 0, set(ax, 'XLim', [0 max(t(end), 1)]); end
        drawnow limitrate
    end
catch err
    if owned, magClose(h); end
    if ishandle(fig), close(fig); end
    rethrow(err);
end

if ishandle(fig), close(fig); end
if owned, magClose(h); end
fprintf('Stopped. %d samples were on screen.\n', height(buf));
end
