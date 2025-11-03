{ python3Packages }: python3Packages.buildPythonPackage rec {
  pname = "asyncio";
  version = "3.4.3";
  src = python3Packages.fetchPypi {
    inherit pname version;
    sha256 = "sha256-gzYP+LyXmA5P8lyWTHvTkj0zPRd6pPf7c2sBnybHy0E=";
  };
}
