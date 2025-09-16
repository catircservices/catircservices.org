{ callPackage
, fetchFromGitHub
, python2
, python2Packages
, ...
}:

let
  packageOverrides = callPackage ./python-packages.nix { };
  python = python2.override { inherit packageOverrides; };
in
  python2Packages.buildPythonPackage {
    pname = "notifico";
    version = "1.0.0";

    src = fetchFromGitHub {
      owner = "whitequark";
      repo = "notifico";
      rev = "46553c7202053e0547d15ecb227e3380a18afc6a";
      hash = "sha256-Wqrd8Ct1rP+s54OP11VVNr7qr1saaA1xjFLNY4E6IXQ=";
    };

    propagatedBuildInputs = with python.pkgs; [
      blinker
      celery
      docopt
      fabric
      Flask
      Flask-Caching
      Flask-Gravatar
      Flask-Mail
      Flask-SQLAlchemy
      Flask-WTF
      Flask-XML-RPC
      gevent
      gunicorn
      oauth2
      PyGithub
      raven
      redis
      requests
      setuptools
      SQLAlchemy
      Unidecode
      utopia
      xmltodict
    ];
  }
