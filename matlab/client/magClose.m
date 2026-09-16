function magClose(h)
%MAGCLOSE  Release the board.
%
%   magClose(h)
%
%   Always safe to call, including on a handle that is already closed.

if nargin < 1 || isempty(h) || ~isstruct(h), return, end

if isfield(h, 'sp') && ~isempty(h.sp)
    try
        if isvalid(h.sp), delete(h.sp); end
    catch
    end
end

if isfield(h, 'pid') && ~isempty(h.pid) && isfile(h.pid)
    try
        pid = str2double(strtrim(fileread(h.pid)));
        if ~isnan(pid) && pid > 1
            system(sprintf('kill %d >/dev/null 2>&1', pid));
        end
        delete(h.pid);
    catch
    end
end

for f = string({h.file, regexprep(char(h.pid), '\.pid$', '.sh')})
    try
        if strlength(f) > 0 && isfile(f), delete(f); end
    catch
    end
end
end
