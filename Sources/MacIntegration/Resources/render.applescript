on run argv
    set inputFile to POSIX file (item 1 of argv)
    set deckName to item 2 of argv
    set outputFile to POSIX file (item 3 of argv)
    tell application "Microsoft PowerPoint"
        open inputFile
        set deck to presentation deckName
        try
            save deck in outputFile as save as PDF
        on error errorText number errorCode
            close deck saving no
            error errorText number errorCode
        end try
        close deck saving no
    end tell
end run
