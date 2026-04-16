import os
import shutil
import zipfile
import subprocess


def _host_uid_gid() -> tuple[int, int] | None:
    """UID/GID for fixing Docker-created root-owned files on the bind mount (Unix only)."""
    try:
        return os.getuid(), os.getgid()
    except AttributeError:
        return None


def _chown_lambda_package_via_docker() -> None:
    """Docker pip install writes files as root; chown inside a container fixes host permissions."""
    ids = _host_uid_gid()
    if not ids or not os.path.isdir("lambda-package"):
        return
    uid, gid = ids
    subprocess.run(
        [
            "docker",
            "run",
            "--rm",
            "-v",
            f"{os.getcwd()}:/var/task",
            "--platform",
            "linux/amd64",
            "--entrypoint",
            "",
            "public.ecr.aws/lambda/python:3.12",
            "/bin/sh",
            "-c",
            f"chown -R {uid}:{gid} /var/task/lambda-package",
        ],
        check=False,
    )


def _rmtree_lambda_package() -> None:
    if not os.path.exists("lambda-package"):
        return
    try:
        shutil.rmtree("lambda-package")
    except PermissionError:
        _chown_lambda_package_via_docker()
        shutil.rmtree("lambda-package")


def main():
    print("Creating Lambda deployment package...")

    # Clean up (may fail if a previous Docker install left root-owned files)
    _rmtree_lambda_package()
    if os.path.exists("lambda-deployment.zip"):
        os.remove("lambda-deployment.zip")

    # Create package directory
    os.makedirs("lambda-package")

    # Install dependencies using Docker with Lambda runtime image
    print("Installing dependencies for Lambda runtime...")

    # Use the official AWS Lambda Python 3.12 image
    # This ensures compatibility with Lambda's runtime environment
    ids = _host_uid_gid()
    chown_suffix = ""
    if ids:
        u, g = ids
        # Without this, pip writes as root on the bind mount and the next deploy cannot rmtree().
        chown_suffix = f" && chown -R {u}:{g} /var/task/lambda-package"

    subprocess.run(
        [
            "docker",
            "run",
            "--rm",
            "-v",
            f"{os.getcwd()}:/var/task",
            "--platform",
            "linux/amd64",  # Force x86_64 architecture
            "--entrypoint",
            "",  # Override the default entrypoint
            "public.ecr.aws/lambda/python:3.12",
            "/bin/sh",
            "-c",
            "export PIP_ROOT_USER_ACTION=ignore; "
            "pip install --target /var/task/lambda-package -r /var/task/requirements.txt "
            "--platform manylinux2014_x86_64 --only-binary=:all: --upgrade"
            + chown_suffix,
        ],
        check=True,
    )

    # Copy application files
    print("Copying application files...")
    for file in ["server.py", "lambda_handler.py", "context.py", "resources.py"]:
        if os.path.exists(file):
            shutil.copy2(file, "lambda-package/")
    
    # Copy data directory
    if os.path.exists("data"):
        shutil.copytree("data", "lambda-package/data")

    # Create zip
    print("Creating zip file...")
    with zipfile.ZipFile("lambda-deployment.zip", "w", zipfile.ZIP_DEFLATED) as zipf:
        for root, dirs, files in os.walk("lambda-package"):
            for file in files:
                file_path = os.path.join(root, file)
                arcname = os.path.relpath(file_path, "lambda-package")
                zipf.write(file_path, arcname)

    # Show package size
    size_mb = os.path.getsize("lambda-deployment.zip") / (1024 * 1024)
    print(f"✓ Created lambda-deployment.zip ({size_mb:.2f} MB)")


if __name__ == "__main__":
    main()