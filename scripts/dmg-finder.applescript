on run argv
	if (count of argv) < 2 then error "usage: dmg-finder.applescript <volumeName> <mountPath>"
	set volumeName to item 1 of argv
	set mountPath to item 2 of argv

	set theXOrigin to 200
	set theYOrigin to 120
	set theWidth to 480
	set theHeight to 360
	set theBottomRightX to (theXOrigin + theWidth)
	set theBottomRightY to (theYOrigin + theHeight)

	set bgPOSIX to mountPath & "/.background/background.png"
	set bgAlias to POSIX file bgPOSIX as alias

	tell application "Finder"
		tell disk volumeName
			open

			tell container window
				set current view to icon view
				set toolbar visible to false
				set statusbar visible to false
				set the bounds to {theXOrigin, theYOrigin, theBottomRightX, theBottomRightY}
			end tell

			set opts to the icon view options of container window
			tell opts
				set icon size to 100
				set text size to 12
				set arrangement to not arranged
				set background picture to bgAlias
			end tell

			set position of item "Clipboard.app" to {120, 158}
			set position of item "Applications" to {328, 158}

			close
			open
			delay 1

			tell container window
				set toolbar visible to false
				set statusbar visible to false
				set the bounds to {theXOrigin, theYOrigin, theBottomRightX, theBottomRightY}
			end tell

			delay 2
		end tell
	end tell

	delay 2
end run
