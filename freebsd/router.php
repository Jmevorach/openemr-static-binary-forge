<?php
// Router for OpenEMR with PHP built-in server
$webRoot = '/build/openemr';
$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$requestFile = $webRoot . $uri;

// Serve existing files directly (CSS, JS, images, etc.)
if ($uri !== '/' && file_exists($requestFile) && !is_dir($requestFile)) {
    return false;
}

// Route to OpenEMR entry point
$openemrEntryPoints = [
    $webRoot . '/interface/main/main.php',
    $webRoot . '/interface/main.php',
    $webRoot . '/main.php',
    $webRoot . '/index.php',
];

// Also check common alternative structures
if (is_dir($webRoot)) {
    $interfaceDir = $webRoot . '/interface';
    if (is_dir($interfaceDir)) {
        if (is_dir($interfaceDir . '/main')) {
            $openemrEntryPoints[] = $interfaceDir . '/main/main.php';
            $openemrEntryPoints[] = $interfaceDir . '/main/index.php';
        }
        $openemrEntryPoints[] = $interfaceDir . '/main.php';
        $openemrEntryPoints[] = $interfaceDir . '/index.php';
    }
}

foreach ($openemrEntryPoints as $entryPoint) {
    if (file_exists($entryPoint)) {
        $_SERVER['SCRIPT_NAME'] = $entryPoint;
        $_SERVER['PHP_SELF'] = $entryPoint;
        $_SERVER['DOCUMENT_ROOT'] = $webRoot;
        require $entryPoint;
        return;
    }
}

http_response_code(404);
echo "OpenEMR entry point not found. Expected: interface/main/main.php\n";
echo "Web root: " . $webRoot . "\n";

