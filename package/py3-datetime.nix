{ python3Packages, fetchPypi }: python3Packages.buildPythonPackage rec {
  pname = "DateTime";
  version = "5.5";

  pyproject = true;
  build-system = [ python3Packages.setuptools ];
  
  src = fetchPypi {
    inherit pname version;
    sha256 = "sha256-IexjMfh6f8tXvXxZ6KaL//5vy/Ws27x7NW1qmgIBkdM=";
  };

  propagatedBuildInputs = with python3Packages; [
    zope-interface
    pytz
  ];
}
