# Script to back up data from Bruker NMR spectrometers to a network drive for easy access for users. Also generates a log of the experiments with basic information, which can, in principle, be used for billing purposes or for troubleshooting (i.e. figuring out what sample was last in the machine before a problem occurred).
# The copying is done using the robocopy program, but rsync could just as easily used. In either case, due to the large number of small files generated by NMR experiments, just passing the data directory paths to the copying program will lead to very long execution times (up to several hours depending on the amount of data), as the copying program must checked the modification date of each individual file passed to it. As such, filtering the data folders by modification date before passing the paths to the copying program is a necessity if the program has to run repeatedly every few minutes. If the data volume is smaller or the use-case is such that the back-up script only needs to run once per day, the filtering can be removed.

param (
    [Parameter(Mandatory=$True)]
    [string]$machine
)

switch ($machine)
{   # Add cases for each machine that requires backing up. Machines can be labelled in many ways. Examples use proton larmor frequency. Each machine can have an arbitrary number of data paths, but must have the same number of source paths and destination paths.
	"400MHz" {
		[string[]]$source_path = '\\IP_address_of_400MHz_machine\path_to_data_directory1\','\\IP_address_of_400MHz_machine\path_to_data_directory2\','\\IP_address_of_400MHz_machine\path_to_data_directory3\'
		[string[]]$dest_path = '\\path_to_network_drive\machine_designation\path_to_data_directory1\','\\path_to_network_drive\machine_designation\path_to_data_directory2\','\\path_to_network_drive\machine_designation\path_to_data_directory3\'
	} "500MHz" {
		[string[]]$source_path = '\\IP_address_of_500MHz_machine\path_to_data_directory1\','\\IP_address_of_500MHz_machine\path_to_data_directory2\'
		[string[]]$dest_path = '\\path_to_network_drive\machine_designation\path_to_data_directory1\','\\path_to_network_drive\machine_designation\path_to_data_directory2\'
	} "test" {
        [string[]]$source_path = 'path_to_testing_data1','path_to_testing_data2'
		[string[]]$dest_path = 'path_to_testing_destination1','path_to_testing_destination2'
    } default {
        [string]$message = "Unknown machine " + $machine
        throw $message
	}
}

# To determine which files need copying, the modification date of folders are checked against the current date-time minus a set number of days. If the modification date is not recent, the folder and it's content are skipped. Folders with recent timestamps are added to a list of modified folders, the subfolders of which are again checked for recent modifications. Only folders in the second layer with recent modification dates are passed to the copying program. A typical way to structure data storage would be to separate the data into folders belonging to individual users, and then separate each user's data into folders by sample name, in which case the first layer of folders is the user folders, and the second layer is the sample folders.
# Due to the way Windows handles modification dates of folders (the creation of a file or subfolder only changes the modification date of the folder one layer up in the directory tree, higher-level directories remain untouched), it is sometimes necessary to scan the subfolders of folders with older timestamps. This could, for instance, be if a user re-uses an existing sample name. In this case, a new folder is created in the sample folder, which updates that folder's modification date, but the user folder is not updated. Users (or whatever first layer of folders) known to exhibit this behaviour can be added to the below list of exemptions to ensure that the folder's subfolders are checked regardless of its timestamp. Similarly, if the data is organised by year before user, the program will decend into the subfolders regardless of the modification date of the "year" folder.

[string]$year_regex = '^(\d{4})$' # regex consisting of 4 numbers.
[string[]]$exemptions = 'list_of_folders_to_decend_into_regardless_of_timestamp' # Comma-separated list of folder names, the subfolders of which are always checked for recent updates.

[string]$robocopy = 'Robocopy.exe' 

[int]$i = 0 # Initiate counting variable for the source/destination lists.

[datetime]$start = Get-Date # Set the start time for the execution of the script.
[datetime]$recent = $start.AddDays(-3) # Define what counts as a folder having been recently changed. Subtracts 3 days from the start date-time.

foreach ($source in $source_path) { # The following instructinos are carried out for each source in the list of sources define above in the switch statement.
    #Initiate empty arrays for lists of modified folders. One for the the folder path starting at the source path, and one for the full folder path.
    [string[]]$modified = @() 
    [string[]]$modifiedfull = @()
    # Get a list of subfolders from the source path and carry out subsuquent instructions for each object.
    Get-ChildItem $source -Directory | ForEach-Object {$_.FullName} {
        [string]$a = $_.FullName.Substring($_.FullName.LastIndexOf('\')+1) # Extract the name of the current object without the leading path information.
        [string]$c = $_.FullName # Store the full path of the current object.
        [datetime]$mod = (Get-Item $c).LastWriteTime # Get the modification date of the current object.
        if (($recent -gt $mod) -and (-not ($exemptions.Contains($a))) -and (-not ($a -match $year_regex))) {
            # If the modification date of the current object is older than $recent and the object name stored in $a is not on the list of exemptions/a year, continue to the next object.
            return
        }
        if ($exemptions.Contains($a) -or $a -match $year_regex) {
            # If the current object is on the list of exemptions, we scan two levels deep from the current object.
            [string]$temp = $a # Copy current folder name.
            # Get a list of subfolders from the source path and carry out subsuquent instructions for each object.
            Get-ChildItem $c -Directory | ForEach-Object {$_.FullName} {
                [string]$a = $temp + "\" + $_.FullName.Substring($_.FullName.LastIndexOf('\')+1)# Extract the name of the current object without the leading path information and add it to name of the parent folder.
                [string]$c = $_.FullName # Store the full path of the current object.
                [datetime]$mod = (Get-Item $c).LastWriteTime # Get the modification date of the current object.
                if ($recent -gt $mod) {
                    # If the modification date of the current object is older than $recent, continue to the next object.
                    return
                } else {
                    # Get a list of subfolders from the source path and carry out subsuquent instructions for each object.
                    Get-ChildItem $c -Directory | ForEach-Object {$_.FullName} {
                        [string]$b = $_.FullName.Substring($_.FullName.LastIndexOf('\')+1) # Extract the name of the current object without the leading path information
                        [datetime]$mod = (Get-Item $_.FullName).LastWriteTime # Get the modification date of the current object.
                        if ($recent -gt $mod) {
                            # If the modification date of the current object is older than $recent, continue to the next object.
                            return
                        } else {
                            # if this code block runs, the folder three layers down in the directory tree has been recently updated, and should be added to the list of folders to pass to the copying program. The variable $d is the directory path starting at $source_path, and $full is the complete path to the recently updated folder.
                            $d = $a + "\" + $b 
                            $full = $source + $d
                            $modified = $modified + $d
                            $modifiedfull = $modifiedfull + $full
                       }
                    }
                }
            }
        } else {
            # Get a list of subfolders from the source path and carry out subsuquent instructions for each object.
            Get-ChildItem $c -Directory | ForEach-Object {$_.FullName} {
                [string]$b = $_.FullName.Substring($_.FullName.LastIndexOf('\')+1) # Extract the name of the current object without the leading path information
                [datetime]$mod = (Get-Item $_.FullName).LastWriteTime # Get the modification date of the current object.
                if ($recent -gt $mod) {
                    # If the modification date of the current object is older than $recent, continue to the next object.
                    return
                } else {
                    # if this code block runs, the folder two layers down in the directory tree has been recently updated, and should be added to the list of folders to pass to the copying program. The variable $d is the directory path starting at $source_path, and $full is the complete path to the recently updated folder.
                    $d = $a + "\" + $b
                    $full = $source + $d
                    $modified = $modified + $d
                    $modifiedfull = $modifiedfull + $full
                }
            }
        }
    }

    [int]$l = 0 # Initiate counting variable for the list of folders to be passed to the copying program.
    foreach ($element in $modifiedfull) { # Loop over the list of full paths to recently updated folders.
        [string]$in = $element # Set input  path to current folder path.
        [string]$out = $dest_path[$i] + $modified[$l] # Set output path to the $dest_path matching the current $source_path plus the path of the current element starting from the $source_path.
        [string[]]$robo_out = "" # Initiate string array to capture output from copying program
        &$robocopy $in $out /R:5 /W:5 /TEE /E /XO /copy:DAT /np /ndl /njh /njs /xx | Out-String -Stream | Tee-Object -Variable robo_out # Run copying program and capture the terminal output in the string array $robo-out.

        [string[]]$copied = @() # Initiate an empty array for a list of folders confirmed to have been copied.
        foreach ($line in $robo_out) { # Loop over the lines stored in the robo_out variable.
            # Copying output contains more than just the path of the copied files. Get the indexes of the first and last character of the path and calculate the path length.
            [int]$path_start = $line.IndexOf("\\")
            [int]$path_end = $line.LastIndexOf("\")+1
            [int]$path_len = $path_end - $path_start
            # If the path starting at $path_start and ending at $path_end is not already contained in $copied and it does not contain the string "pdata" (a subfolder generated the experiment), add it to $copied.
            if (-not $copied.Contains($line.Substring($path_start,$path_len)) -and (-not $line.Substring($path_start,$path_len).Contains("pdata"))) {
                $copied += $line.Substring($path_start,$path_len)
            }
        }
        echo $copied # Print $copied to terminal.
        foreach ($entry in $copied) { # Loop over paths stored in $copied.
            # Initiate variables to store info about the experiment corresponding to the current path.
            [string]$filename = ""
            [string]$acqu = ""
            [string]$proc = ""
            [string]$solvent = ""
            [string]$nucleus = ""
            [string]$filesizeacq = ""
            [string]$filesizeproc = ""
            [string]$instrument = ""
            [nullable[datetime]]$timeofstart = $null
            [string]$timeofstartstr = ""
            [nullable[datetime]]$timeofend = $null
            [string]$timeofendstr = ""
            [string]$outstring = ""

            # Set variables $filename, $acqu, and $proc to the paths of the current experiment and its associated acqu and proc files.
            $filename = $entry
            $acqu = $entry + "acqu"
            $proc = $entry + "pdata\1\proc"
            $solvent = (Select-String -Path $acqu -Pattern "SOLVENT=" -SimpleMatch).Line # Get the line containing solvent info from the acqu file.
            $solvent = [regex]::matches($solvent,'(?<=<).+?(?=>)').value # Extract just the solvent name from the above line.
            $nucleus = (Select-String -Path $acqu -Pattern "NUC1=").Line # Get the line containing info about the observed nucleus from the acqu file.
            $nucleus = [regex]::matches($nucleus,'(?<=<).+?(?=>)').value # Extract the nucleus name from the above line.
            $filesizeacq = (Select-String -Path $acqu -Pattern "TD=" -Exclude "NusTD=").Line.split(" ")[-1] # Get the number of data points in the FID from the acqu file.
            $filesizeproc = (Select-String -Path $proc -Pattern "FTSIZE=").Line.split(" ")[1] # Get the number of data points in the processed spectrum from the proc file.
            $instrument = "Instrument_designation_" + $machine # Set the name of the instrument from which the data originated.
            $timeofstart = (Get-Item ($entry + "precom.output")).LastWriteTime # Get the experiment start time from the timestamp of the precompilation file, which is generated right before the experiment is run.
            $timeofstartstr = $timeofstart.ToString("yyyy/MM/dd HH:mm:ss") # Convert the datetime to string.
            $timeofend = (Get-Item ($entry + "fid")).LastWriteTime # Get the experiment end time from the modification date of the FID file, which contains the raw data generated by the experiment.
            $timeofendstr = $timeofend.ToString("yyyy/MM/dd HH:mm:ss") # Convert the datetime to string.

            [string]$outstring = $filename + "," + $solvent + "," + $nucleus + "," + $filesizeacq + "," + $filesizeproc + "," + $instrument + "," + $timeofstartstr + "," + $timeofendstr # Set $outstring to comma separated experiment parameters obtained above. 
            [string]$reportfile = "\\rdcs\centres\she\LIMS_NMR\Backup\Logs\" + $instrument + ".csv" # Set path of log file to store experiment info.
            # If none of the experiment parameters obtained above are empty, append $outstring to the log file.
            if (!(!$filename -or !$solvent -or !$nucleus -or !$filesizeacq -or !$filesizeproc -or !$instrument -or !$timeofstartstr -or !$timeofendstr)) {
                Out-File -FilePath $reportfile -InputObject $outstring -Append -Encoding ASCII
            }
        }
        [string[]]$copied = @() # Empty $copied string array.
        $l += 1 # Increment folder counting variable.
    }
    $i += 1 # Increment $source_path counting variable.
}

[datetime]$end = Get-Date # Set end time for the execcution of the script.
$runtime = $end - $start # Calculate the runtime by subtracting the start time from the end time.

echo $runtime # Print the runtime to terminal. This is useful to determine whether the runtime is shorter than the back-up interval.
