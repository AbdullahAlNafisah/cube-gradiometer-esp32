function S = magRead(h, n)
%MAGREAD  Read the most recent samples.
%
%   S = magRead(h)        the latest sample
%   S = magRead(h, 100)   the latest 100 samples
%
%   Returns a table: t_ms, then <name>_x_uT, _y_uT, _z_uT, _norm_uT, _temp_C for
%   every sensor. Field values are microtesla, temperature is Celsius. A sensor
%   that is disconnected reads NaN, so the table is always the same width.
%
%   Example:
%       h = magOpen;
%       S = magRead(h, 50);
%       plot(S.t_ms/1000, S.East_norm_uT)
%       magClose(h)
%
%   See also MAGOPEN, MAGCLOSE, MAGLIVE.

if nargin < 2 || isempty(n), n = 1; end
nCols = numel(h.cols);

if h.mode == "serialport"
    rows = readDirect(h.sp, nCols, n);
else
    rows = readStream(h.file, nCols, n);
end

S = array2table(rows, 'VariableNames', cellstr(h.cols));
end

% ---------------------------------------------------------------------------------
function rows = readDirect(sp, nCols, n)
rows = nan(n, nCols);
flush(sp);
k = 0; t0 = tic;
while k < n
    if toc(t0) > 10 + n/10
        error("mag:timeout", "Got %d of %d samples. Is the board still streaming?", k, n);
    end
    v = parseLine(readQuiet(sp), nCols);
    if isempty(v), continue, end
    k = k + 1;
    rows(k, :) = v;
end
end

% ---------------------------------------------------------------------------------
function rows = readStream(file, nCols, n)
%READSTREAM  Take the last n good rows from the tail of the capture file.
t0 = tic;
while toc(t0) < 10
    lines = tailLines(file, n + 20);
    good  = nan(numel(lines), nCols);
    k = 0;
    for i = 1:numel(lines)
        v = parseLine(lines(i), nCols);
        if isempty(v), continue, end
        k = k + 1;
        good(k, :) = v;
    end
    if k >= n
        rows = good(k-n+1:k, :);
        return
    end
    pause(0.05);
end
error("mag:timeout", "Only %d of %d samples available. Is the board still streaming?", k, n);
end

% ---------------------------------------------------------------------------------
function lines = tailLines(file, want)
%TAILLINES  Read roughly the last `want` lines without loading the whole file.
fid = fopen(file, 'r');
if fid < 0, lines = strings(0,1); return, end
closer = onCleanup(@() fclose(fid));
fseek(fid, 0, 'eof');
nbytes = ftell(fid);
chunk  = min(nbytes, want*220 + 4096);
fseek(fid, nbytes - chunk, 'bof');
txt = fread(fid, chunk, '*char').';
lines = split(string(txt), newline);
if numel(lines) > 1
    lines = lines(1:end-1);   % last element is an unterminated partial write
end
end

% ---------------------------------------------------------------------------------
function v = parseLine(line, nCols)
%PARSELINE  A data row, or empty for banners, headers and partial lines.
v = [];
line = strtrim(line);
if strlength(line) == 0,                           return, end
if startsWith(line, "#") || startsWith(line, "t"), return, end
x = str2double(split(line, ","));
if numel(x) ~= nCols || isnan(x(1)),               return, end
v = x.';
end

% ---------------------------------------------------------------------------------
function line = readQuiet(sp)
ws = warning('off', 'transportlib:client:ReadWarning');
restoreW = onCleanup(@() warning(ws));
try
    line = string(readline(sp));
catch
    line = "";
end
if isempty(line) || ismissing(line), line = ""; end
end
