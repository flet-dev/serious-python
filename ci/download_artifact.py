import json
import os
import pathlib
import sys
import tarfile
import urllib.request

if len(sys.argv) < 2:
    print("Specify artifact job name and artifact deployment name to download")
    sys.exit(1)

artifact_job_name = sys.argv[1]
artifact_file_name = sys.argv[2].format(
    version=os.environ.get("APPVEYOR_BUILD_VERSION")
)

build_jobs = {}


def download_job_artifact(job_id, file_name, dest_file):
    url = f"https://ci.appveyor.com/api/buildjobs/{job_id}/artifacts/{file_name}"
    print(f"Downloading {url}...")
    urllib.request.urlretrieve(url, dest_file)


def get_build_job_ids():
    account_name = os.environ.get("APPVEYOR_ACCOUNT_NAME")
    project_slug = os.environ.get("APPVEYOR_PROJECT_SLUG")
    build_id = os.environ.get("APPVEYOR_BUILD_ID")
    url = f"https://ci.appveyor.com/api/projects/{account_name}/{project_slug}/builds/{build_id}"
    print(f"Fetching build details at {url}")
    req = urllib.request.Request(url)
    req.add_header("Content-type", "application/json")
    project = json.loads(urllib.request.urlopen(req).read().decode())
    for job in project["build"]["jobs"]:
        build_jobs[job["name"]] = job["jobId"]


current_dir = pathlib.Path(os.getcwd())
print("current_dir", current_dir)

get_build_job_ids()

# create "web" directory
dist_path = current_dir.joinpath("python_dist")
dist_path.mkdir(exist_ok=True)
tar_path = current_dir.joinpath(artifact_file_name)
download_job_artifact(build_jobs[artifact_job_name], artifact_file_name, tar_path)
with tarfile.open(tar_path, "r:gz") as tar:
    tar.extractall(str(dist_path))
os.remove(tar_path)
