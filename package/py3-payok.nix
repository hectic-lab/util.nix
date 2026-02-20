{ python3Packages, fetchPypi }: python3Packages.buildPythonPackage rec {
  pname = "payok";
  version = "1.2";

  pyproject = true;
  build-system = [ python3Packages.setuptools ];
  
  src = fetchPypi {
    inherit pname version;
    sha256 = "sha256-UN+MSNGhrPpw7hZRLAx8XY3jC0ldo+DlbaSJ64wWBHo=";
  };
  
  propagatedBuildInputs = with python3Packages; [ requests ];
  
  doCheck = false;
}
