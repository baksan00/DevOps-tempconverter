from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def test_dockerfile_exists_and_exposes_5000():
    dockerfile = ROOT / "Dockerfile"
    assert dockerfile.exists()
    content = dockerfile.read_text()
    assert "EXPOSE 5000" in content
    assert "pip install" in content
    assert "apt-get upgrade" in content or "dnf update" in content

def test_requirements_have_flask_and_mysql_driver():
    content = (ROOT / "requirements.txt").read_text()
    assert "Flask" in content
    assert "pymysql" in content

def test_html_title_is_tempconverter():
    content = (ROOT / "templates" / "index.html").read_text()
    assert "<title>TempConverter</title>" in content
