function magBaseline(outFile)
%MAGBASELINE  Error budget against baseline, and the figure the README uses.
%
%   magBaseline              write docs/baseline.png next to the repo's docs
%   magBaseline("out.png")   write somewhere else
%
%   Four terms set how short the baseline can usefully be. Two of them fall as
%   1/d, so a longer baseline helps; truncation rises as d^2, so it does not.
%   The crossing of those trends is the whole argument for 3 cm.
%
%   Needs no hardware. Prints the values it plots, so the README prose and the
%   figure are read off the same constants and cannot drift apart.

% --- constants, quoted in README.md ------------------------------------------
SIGMA  = 0.19;      % uT rms per axis, BMM350 X and Y at BW = ODR/2
OFFSET = 1.0;       % uT of hard-iron mismatch between one opposing pair
CUBE   = 0.03;      % m, the cube this firmware runs on

% Reference source: a dipole raising the field B_REF at R_REF. For B ~ r^-3 the
% third derivative is 60*B/r^3, and a central difference of the first derivative
% truncates at (d^2/24)*B'''.
B_REF = 50.0;  R_REF = 0.10;
D3B    = 60 * B_REF / R_REF^3;
SIGNAL = 3 * B_REF / R_REF;

% The four terms, as functions of baseline d so the curves and the numbers
% printed below come from one definition each.
noise      = @(d) sqrt(2) * SIGMA ./ d;          % two sensors differenced
offset     = @(d) OFFSET ./ d;                   % hard-iron mismatch
truncation = @(d) D3B .* d.^2 / 24;              % finite-difference error
signal     = @(d) SIGNAL * ones(size(d));        % what there is to measure

d = logspace(log10(2e-3), log10(4e-1), 400);     % baseline, m

% --- figure ------------------------------------------------------------------
INK = [0.54 0.56 0.60]; ORANGE = [0.85 0.55 0.17];
GREEN = [0.30 0.69 0.49]; RED = [0.85 0.33 0.31];

fig = figure('Color', 'w', 'Position', [100 100 760 470], 'Visible', 'off', ...
             'InvertHardcopy', 'off');          % keep the white we set, don't re-map it
ax  = axes(fig); hold(ax, 'on');

loglog(ax, d*100, signal(d),     '--', 'Color', INK,    'LineWidth', 1.6);
loglog(ax, d*100, truncation(d),       'Color', GREEN,  'LineWidth', 2.0);
loglog(ax, d*100, offset(d),           'Color', RED,    'LineWidth', 2.0);
loglog(ax, d*100, noise(d),            'Color', ORANGE, 'LineWidth', 2.0);

set(ax, 'XScale', 'log', 'YScale', 'log', ...
        'XLim', [0.2 40], 'YLim', [1e-1 1e5], ...
        'XTick', [0.2 1 3 10 30], 'XTickLabel', {'2 mm','1 cm','3 cm','10 cm','30 cm'}, ...
        'XGrid', 'on', 'YGrid', 'on', 'GridLineStyle', ':', 'GridAlpha', 0.25, ...
        'Box', 'off', 'XColor', INK, 'YColor', INK, ...
        'Color', 'w', 'GridColor', INK);   % R2026 defaults to a dark theme
xlabel(ax, 'baseline d');
ylabel(ax, '\muT/m');

% Where this cube actually sits, and what each term reads there.
xline(ax, CUBE*100, 'Color', INK, 'LineWidth', 1.2, 'Alpha', 0.5, ...
      'Label', 'built at 3 cm', 'LabelHorizontalAlignment', 'center', ...
      'LabelVerticalAlignment', 'top', 'FontSize', 10, 'Interpreter', 'none', ...
      'HandleVisibility', 'off');
for term = {{truncation, GREEN}, {offset, RED}, {noise, ORANGE}, {signal, INK}}
    f = term{1}{1}; c = term{1}{2};
    plot(ax, CUBE*100, f(CUBE), 'o', 'MarkerSize', 6, 'MarkerFaceColor', c, ...
         'MarkerEdgeColor', 'none', 'HandleVisibility', 'off');
end

legend(ax, { ...
    sprintf('signal, dipole 50 \\muT at 10 cm   %6.0f \\muT/m', signal(CUBE)), ...
    sprintf('truncation, O(d^2)   %6.0f \\muT/m', truncation(CUBE)), ...
    sprintf('hard-iron offset floor, 1 \\muT mismatch   %6.0f \\muT/m', offset(CUBE)), ...
    sprintf('sensor noise floor, \\surd2\\sigma/d   %6.0f \\muT/m', noise(CUBE))}, ...
    'Location', 'southoutside', 'Box', 'off', 'TextColor', INK, 'FontSize', 10);

title(ax, 'Error terms against baseline', 'Color', INK, 'FontWeight', 'normal');
subtitle(ax, sprintf(['Both floors fall as 1/d, truncation rises as d^2. ' ...
                      'Offset sits %.1f\\times above noise at every d: that, not noise, ' ...
                      'is the limit.'], offset(CUBE)/noise(CUBE)), ...
         'Color', INK, 'FontSize', 10);

% --- write -------------------------------------------------------------------
if nargin < 1 || strlength(string(outFile)) == 0
    here    = fileparts(mfilename('fullpath'));          % matlab/analysis
    outFile = fullfile(here, '..', '..', 'docs', 'baseline.png');
end
exportgraphics(fig, char(outFile), 'Resolution', 150, 'BackgroundColor', 'white');
close(fig);
fprintf('wrote %s\n', char(outFile));

% --- the numbers the README quotes -------------------------------------------
fprintf('\nAt d = %g cm:\n', CUBE*100);
fprintf('  sensor noise      %7.1f uT/m\n', noise(CUBE));
fprintf('  hard-iron offset  %7.1f uT/m   <- the floor that actually limits it\n', offset(CUBE));
fprintf('  truncation        %7.1f uT/m\n', truncation(CUBE));
fprintf('  signal            %7.1f uT/m\n', signal(CUBE));
end
