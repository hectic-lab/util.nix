{ self,fetchPypi, python3Packages, system }: python3Packages.buildPythonPackage rec {
    pname = "marzban";
    version = "0.4.3";
    
    src = fetchPypi {
      inherit pname version;
      sha256 = "sha256-z71Wl4AuET3oES7/48u+paL9F12SdrkohcEee/tkWVk=";
    };

    pyproject = true;
    build-system = [ python3Packages.setuptools ];
    
    propagatedBuildInputs = with python3Packages; [
      httpx
      paramiko
      sshtunnel
    ];
    nativeBuildInputs = (with python3Packages; [
      setuptools
      wheel
      setuptools-scm
      httpx
      pydantic
      paramiko
      sshtunnel
    ]) ++ (with self.packages.${system}; [
      py3-datetime
    ]);

    doCheck = false;
  }
