import os
import platform
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
TASK = os.path.basename(HERE)
PLUGIN = os.path.join(ROOT, "plugins", "dash", "dash.plugin.zsh")

MUTANTS = [
    ("completion position -ne 2 -> -ne 3", "$CURRENT -ne 2", "$CURRENT -ne 3"),
    ("keyword guard =~ \":\" -> =~ \";\"", '=~ ":"', '=~ ";"'),
]


def repo_state():
    out = subprocess.run(
        ["git", "status", "--porcelain", "--", "plugins", "lib"],
        cwd=ROOT, capture_output=True, text=True,
    )
    return out.stdout


def run_test(zsh, tmp, plugin):
    env = {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": tmp,
        "TMPDIR": tmp,
        "ZDOTDIR": tmp,
        "ZSH": ROOT,
        "DASH_PLUGIN": plugin,
    }
    return subprocess.run(
        [zsh, "-f", os.path.join(HERE, "test.zsh")],
        env=env, cwd=tmp, capture_output=True, text=True,
    )


def main():
    before = repo_state()
    zsh = shutil.which("zsh")
    if not zsh:
        print("zsh not found")
        return 1
    problems = []
    mutant_report = []
    with tempfile.TemporaryDirectory() as tmp:
        proc = run_test(zsh, tmp, PLUGIN)
        source = open(PLUGIN).read()
        for name, old, new in MUTANTS:
            if source.count(old) != 1:
                problems.append("mutation target not found: " + name)
                continue
            path = os.path.join(tmp, "mutant.plugin.zsh")
            with open(path, "w") as fh:
                fh.write(source.replace(old, new))
            result = run_test(zsh, tmp, path)
            killed = result.returncode != 0 or "FAIL " in result.stdout
            failing = [l for l in result.stdout.splitlines() if l.startswith("FAIL ")]
            mutant_report.append("mutant [%s]: %s (%d failing assertions)" % (name, "rejected" if killed else "SURVIVED", len(failing)))
            if not killed:
                problems.append("mutant survived: " + name)
    after = repo_state()
    lines = proc.stdout.splitlines()
    passed = [l for l in lines if l.startswith("PASS ")]
    failed = [l for l in lines if l.startswith("FAIL ")]
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
    ] + mutant_report + [""] + lines
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
