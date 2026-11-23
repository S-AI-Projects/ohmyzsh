import os
import platform
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
TASK = os.path.basename(HERE)


def repo_state():
    out = subprocess.run(
        ["git", "status", "--porcelain", "--", "plugins", "lib"],
        cwd=ROOT, capture_output=True, text=True,
    )
    return out.stdout


def main():
    before = repo_state()
    zsh = shutil.which("zsh")
    if not zsh:
        print("zsh not found")
        return 1
    with tempfile.TemporaryDirectory() as tmp:
        env = {
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": tmp,
            "TMPDIR": tmp,
            "ZDOTDIR": tmp,
            "ZSH": ROOT,
        }
        proc = subprocess.run(
            [zsh, "-f", os.path.join(HERE, "test.zsh")],
            env=env, cwd=tmp, capture_output=True, text=True,
        )
    after = repo_state()
    lines = proc.stdout.splitlines()
    passed = [l for l in lines if l.startswith("PASS ")]
    failed = [l for l in lines if l.startswith("FAIL ")]
    problems = []
    if proc.returncode != 0:
        problems.append("zsh exited with %d" % proc.returncode)
    if failed:
        problems.append("%d assertions failed" % len(failed))
    if not any(l.startswith("PASS success:") for l in passed):
        problems.append("no success case executed")
    if not any(l.startswith("PASS edge:") for l in passed):
        problems.append("no edge case executed")
    if before != after:
        problems.append("repository state changed during the run")
    version = subprocess.run([zsh, "--version"], capture_output=True, text=True).stdout.strip()
    report = [
        "task: " + TASK,
        "command: zsh -f work/%s/test.zsh (ZSH=<checkout>, HOME/TMPDIR/ZDOTDIR=<temp dir>)" % TASK,
        "zsh: " + version,
        "python: " + platform.python_version(),
        "platform: " + platform.system(),
        "exit status: %d" % proc.returncode,
        "passed: %d, failed: %d" % (len(passed), len(failed)),
        "repository state before == after: %s" % (before == after),
        "",
    ] + lines
    if proc.stderr.strip():
        report += ["", "stderr:", proc.stderr.strip()]
    with open(os.path.join(HERE, "evidence.txt"), "w") as fh:
        fh.write("\n".join(report) + "\n")
    print("\n".join(report))
    if problems:
        print("\nFAILED: " + "; ".join(problems))
        return 1
    print("\nOK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
