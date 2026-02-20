{ 
    lib,
    python3Packages,
    fetchFromGitHub,
}: python3Packages.buildPythonPackage rec {
  pname = "shap-e";
  version = "1.0";

  pyproject = true;
  build-system = [ python3Packages.setuptools ];

  src = fetchFromGitHub {
    inherit pname version;
    owner = "openai";
    repo = "shap-e";
    rev = "50131012ee11c9d2617f3886c10f000d3c7a3b43";
    sha256 = "sha256-RN4dARvz5fzoAFtEOdHWDuMqchCBuoGjsBv/yeWWai0=";
  };

  propagatedBuildInputs = with python3Packages; [
    filelock
    pillow
    torch
    fire
    humanize
    requests
    tqdm
    matplotlib
    scikit-image
    scipy
    numpy
    blobfile
    clip

    # NOTE(yukkop): not declared in setup.py, but crash on runtime without that
    ipywidgets
  ];

  meta = with lib; {
    description = "Shape-e OpenAi model";
    platforms = platforms.all;
  };
}
