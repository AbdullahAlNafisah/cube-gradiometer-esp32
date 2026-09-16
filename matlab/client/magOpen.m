function h = magOpen(port)
%MAGOPEN  Connect to the magnetometer board.
%
%   h = magOpen            find the board automatically
%   h = magOpen("COM5")    or name the port
%
%   Returns a handle to pass to magRead and magClose. The handle carries the
%   sensor names the firmware reported, so h.names tells you what is connected.
%
%   Pass the handle to magClose when you are done.
%
%   See also MAGREAD, MAGCLOSE, MAGLIVE, MAGPORTS.

if nargin < 1, port = ""; end
port = string(port);

if strlength(port) > 0
    cands = port;
else
    cands = magPorts();
    if isempty(cands)
        error("mag:noPorts", "No USB serial ports found. Is the board plugged in?");
    end
end

lastErr = "";
for c = reshape(cands, 1, [])
    try
        h = openDirect(c);
        return
    catch err
        lastErr = err.message;
        if isunix && contains(err.message, "lock file", "IgnoreCase", true)
            try
                h = openStream(c);      % no lock file, no root needed
                return
            catch err2
                lastErr = err2.message;
            end
        end
    end
end
error("mag:notFound", "Could not read the board on %s.\n\n%s", strjoin(cands, ", "), lastErr);
end

% ---------------------------------------------------------------------------------
function h = openDirect(port)
%OPENDIRECT  The normal path: MATLAB's own serialport object.
sp = serialport(port, 115200, "Timeout", 2);
configureTerminator(sp, "LF");
hdr = "";
for attempt = 1:3
    flush(sp); write(sp, 'h', "char");
    t0 = tic;
    while toc(t0) < 2.5
        line = readQuiet(sp);
        if startsWith(line, "t_ms"), hdr = line; break, end
    end
    if strlength(hdr) > 0, break, end
end
if strlength(hdr) == 0
    delete(sp);
    error("mag:noHeader", "No CSV header on %s.", port);
end
h = makeHandle("serialport", port, hdr);
h.sp = sp;
end

% ---------------------------------------------------------------------------------
function h = openStream(port)
%OPENSTREAM  Fallback for Linux when MATLAB cannot create its /run/lock file.
%   A background reader copies the device to a temp file and magRead tails it.
%   -hupcl keeps the port from dropping DTR and resetting the board.
sweepStaleReaders();      % a reader left behind by a crash would steal our bytes

tag    = sprintf('magstream_%s', char(java.util.UUID.randomUUID.toString.substring(0,8)));
file   = fullfile(tempdir, [tag '.csv']);
pidf   = fullfile(tempdir, [tag '.pid']);
script = fullfile(tempdir, [tag '.sh']);

% The script records its own pid and then execs, so the pid stays valid once it
% has become `cat`. Without this there is nothing to kill: a plain
% sh -c 'cat PORT > FILE' execs into bare `cat`, and the tag that would have
% identified it is gone from the command line.
fid = fopen(script, 'w');
if fid < 0, error("mag:stream", "Cannot write the reader script."); end
fprintf(fid, '#!/bin/sh\necho $$ > "$3"\nexec cat "$1" > "$2"\n');
fclose(fid);

cmd = sprintf(['stty -F %s 115200 raw -echo -hupcl min 0 time 10 2>/dev/null && ' ...
               'chmod +x %s && setsid %s %s %s %s >/dev/null 2>&1 &'], ...
               port, script, script, port, file, pidf);
[st, ~] = system(cmd);
if st ~= 0
    error("mag:stream", "Could not start the reader on %s.", port);
end

pause(0.4);
system(sprintf('printf h > %s 2>/dev/null', port));

hdr = ""; t0 = tic;
while toc(t0) < 8
    if isfile(file)
        lines = readlines(file);
        % The final element is whatever has been written since the last newline,
        % so it can be half a line. A truncated header still starts with "t_ms",
        % which would silently give the wrong column count, so drop it and
        % require the last column the firmware prints.
        if numel(lines) > 1, lines = lines(1:end-1); end
        hit = lines(startsWith(strtrim(lines), "t_ms"));
        for j = 1:numel(hit)
            cand = strtrim(hit(j));
            if endsWith(cand, "_temp_C") && numel(split(cand, ",")) >= 6
                hdr = cand; break
            end
        end
        if strlength(hdr) > 0, break, end
    end
    pause(0.2);
end
if strlength(hdr) == 0
    killPidFile(pidf);
    error("mag:noHeader", ...
          ['No CSV header from %s.\n\nCheck nothing else holds the port ' ...
           '(close pio device monitor) and that you are in its group ' ...
           '(ls -l %s, then groups).'], port, port);
end

h      = makeHandle("stream", port, hdr);
h.file = file;
h.pid  = pidf;
h.tag  = tag;
warning("mag:streamMode", ...
        ['Reading %s through a background reader: MATLAB cannot create its lock ' ...
         'file in /run/lock. This works fine.\nFor the direct path, run in a ' ...
         'terminal:\n    sudo chgrp uucp /run/lock && sudo chmod 0775 /run/lock'], port);
end

% ---------------------------------------------------------------------------------
function h = makeHandle(mode, port, hdr)
cols = strtrim(split(hdr, ","));
h = struct('mode',  mode, ...
           'port',  port, ...
           'cols',  {cols}, ...
           'names', {unique(extractBefore(cols(2:end), "_"), "stable")}, ...
           'sp',    [], ...
           'file',  '', ...
           'pid',   '', ...
           'tag',   '');
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

% ---------------------------------------------------------------------------------
function sweepStaleReaders()
%SWEEPSTALEREADERS  Kill readers left over from a crashed or force-quit session.
d = dir(fullfile(tempdir, 'magstream_*.pid'));
for i = 1:numel(d)
    killPidFile(fullfile(d(i).folder, d(i).name));
end
end

% ---------------------------------------------------------------------------------
function killPidFile(pidf)
%KILLPIDFILE  Stop the reader named by a pid file and clear its temp files.
try
    if isfile(pidf)
        pid = str2double(strtrim(fileread(pidf)));
        if ~isnan(pid) && pid > 1
            system(sprintf('kill %d >/dev/null 2>&1', pid));
        end
        delete(pidf);
    end
catch
end
base = erase(string(pidf), ".pid");
for ext = [".csv" ".sh"]
    try
        f = base + ext;
        if isfile(f), delete(f); end
    catch
    end
end
end
