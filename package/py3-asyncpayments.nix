{ python3Packages, fetchPypi }: python3Packages.buildPythonPackage rec {
    pname = "asyncpayments";
    version = "1.4.6";
    
    src = fetchPypi {
      inherit pname version;
      sha256 = "sha256-t7AZiRb7DHZgJHPNQwAEuc0mrTQ14+82d19VomTjs8U=";
    };

    format = "pyproject";
    
    nativeBuildInputs = with python3Packages; [ setuptools wheel setuptools-scm ];
    propagatedBuildInputs = with python3Packages; [ aiohttp requests ];
    
    doCheck = false;
}
