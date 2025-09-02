<?php

//Put me in the website root, this is a document that is referenced by the webserver
//This is a simple directory listing script that displays files and directories in the current directory
//also remember that there is a globalVariables.php file that is required once, you wil need to add this also


echo "<h2><serverName></h2>";

// Get the current directory
$directory = getcwd();

//require once the "globalVariables.php" file to import global variables
require_once '/var/www/html/globalVariables.php';



// Scan directory and exclude ignored files
$scanned_directory = array_diff(scandir($directory), $ignore);

// Check if there is a parent directory and add it
if (realpath($directory) !== realpath($_SERVER['DOCUMENT_ROOT'])) {
    echo '<p ><span id="PD" class="material-symbols-outlined">arrow_back</span><a href="../">Parent Directory</a></p>';
}

// Display a styled directory listing like Apache's default
echo '<ul>';
foreach ($scanned_directory as $file) {
    // Determine if it's a directory or file
    if (is_dir($file)) {
        // Display directory link
        echo '<li><span  class="material-symbols-outlined folderIcon">folder</span><a href="' . $file . '/">' . $file . '/</a></li>';
    } else {
        // Display file link with size
        $filesize = filesize($file);
        echo '<li><span  class="material-symbols-outlined fileIcon">draft</span><a href="' . $file . '">' . $file . '</a> (' . formatSizeUnits($filesize) . ')</li>';
    }
}
echo '</ul>';

// Function to format file size in human-readable form
function formatSizeUnits($bytes)
{
    if ($bytes >= 1073741824) {
        $bytes = number_format($bytes / 1073741824, 2) . ' GB';
    } elseif ($bytes >= 1048576) {
        $bytes = number_format($bytes / 1048576, 2) . ' MB';
    } elseif ($bytes >= 1024) {
        $bytes = number_format($bytes / 1024, 2) . ' KB';
    } elseif ($bytes > 1) {
        $bytes = $bytes . ' bytes';
    } elseif ($bytes == 1) {
        $bytes = $bytes . ' byte';
    } else {
        $bytes = '0 bytes';
    }
    return $bytes;
}
?>
<!DOCTYPE html>

<html>

<head>


    <meta charset="utf-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <title><serverName></title>
    <meta name="description" content="">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="">
    <!--Get fonts from google fonts-->
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Roboto:ital,wght@0,100;0,300;0,400;0,500;0,700;0,900;1,100;1,300;1,400;1,500;1,700;1,900&display=swap" rel="stylesheet">
    <!--Get icons from google fonts-->
    <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@24,400,0,0" />
    <link rel="stylesheet" href="https://fonts.googleapis.com/icon?family=Material+Icons">
</head>

<body>
    <style>
        * {
            font-family: 'Roboto', Courier, monospace;
            font-weight: 300;
            color: white;
            background-color: #181818;

        }

        ul {
            list-style-type: none;
        }

        li {
            margin: 5px 0;
        }

        a {
            text-decoration: none;
            color: rgb(255, 255, 255);
            font-size: larger;
        }

        a:hover {
            text-decoration: underline;
            color: rgb(143, 143, 143);
        }

        .folderIcon {
            color: purple;
        }

        .fileIcon {
            color: pink;
        }

        #PD {
            font-size: small;
        }

        .material-symbols-outlined {
            font-variation-settings:
                'FILL' 0,
                'wght' 400,
                'GRAD' 0,
                'opsz' 40
        }
    </style>
</body>

</html>