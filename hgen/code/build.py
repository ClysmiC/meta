import os
import subprocess


# @HardCoded path... odin doesn't let us use Windows style path for -out param? W:/RTS/build/hgen.exe is an error due to the ':' character...
# https://github.com/odin-lang/Odin/issues/874

# NOTE - Script should be in the same dir as all the code!
thisDir = os.path.dirname(__file__)

# Build debug
subprocess.run([
				"C:/Tools/Odin/odin.exe",
					"build",
					str(thisDir),
					f"-out:{str(thisDir)}/../bin/hgen_debug.exe",
					"-debug",
				])

# Build non-debug
subprocess.run([
				"C:/Tools/Odin/odin.exe",
					"build",
					str(thisDir),
					f"-out:{str(thisDir)}/../bin/hgen.exe"
				])
