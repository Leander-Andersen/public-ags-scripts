<?php
// -------------------------------
// 1. API KEY CHECK
// -------------------------------
$expectedToken = 'BRRRRR_skibidi_dop_dop_dop_yes_yes!';

// Read all request headers
$headers = function_exists('getallheaders') ? getallheaders() : [];

// Extract the API key header
$token = isset($headers['X-Api-Key']) ? $headers['X-Api-Key'] : '';

// Reject if token is wrong
if ($token !== $expectedToken) {
    http_response_code(401);
    echo "Unauthorized";
    exit;
}

// -------------------------------
// 2. READ JSON FROM POWERSHELL
// -------------------------------
$rawInput = file_get_contents("php://input");
$data     = json_decode($rawInput, true);

// Validate JSON
if (!is_array($data)) {
    http_response_code(400);
    echo "Bad Request";
    exit;
}
// -------------------------------
// 3. Extract variables
// -------------------------------
$script = $data['script'];
$host   = $data['host'];
$ok     = $data['ok'];
$error  = $data['error'];

// -------------------------------
// 4. WRITE TO DATABASE
// -------------------------------

require_once("db.php");

$sql = "INSERT INTO TestAPI (ComputerName, Scriptname, RanWithoutIssues, Error) VALUES ('$host', '$script', '$ok', '$error')";

    $result = mysqli_query($conn, $sql);

    // Close connection
    mysqli_close($conn);
