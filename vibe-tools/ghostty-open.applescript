on run argv
    tell application "Ghostty"
        set surfaceConfig to new surface configuration
        set command of surfaceConfig to item 1 of argv
        set initial working directory of surfaceConfig to item 2 of argv
        if (count of windows) > 0 then
            new tab in front window with configuration surfaceConfig
        else
            new window with configuration surfaceConfig
        end if
        activate
    end tell
end run
