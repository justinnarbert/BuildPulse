#!/bin/bash

# Enable double globbing
shopt -s globstar

set -e

# Enable double globbing if supported by the shell on the base github runner
if shopt -s globstar; then
	echo "This bash shell version supports double globbing: '${BASH_VERSION}'."

else
  echo "This bash shell version does not support double globbing: '${BASH_VERSION}'. Please upgrade to bash 4+."
fi

if ! echo $BPTR_INPUT_ACCOUNT | egrep -q '^[0-9]+$'
then
	echo "?? The given value is not a valid account ID: ${BPTR_INPUT_ACCOUNT}"
	echo "?? To resolve this issue, set the 'account' parameter to your numeric BuildPulse Account ID."
	exit 1
fi
ACCOUNT_ID=$BPTR_INPUT_ACCOUNT

echo "1. account: $ACCOUNT_ID"

if ! echo $BPTR_INPUT_REPOSITORY | egrep -q '^[0-9]+$'
then
	echo "?? The given value is not a valid repository ID: ${BPTR_INPUT_REPOSITORY}"
	echo "?? To resolve this issue, set the 'repository' parameter to your numeric BuildPulse Repository ID."
	exit 1
fi
REPOSITORY_ID=$BPTR_INPUT_REPOSITORY

echo "2. repository: $REPOSITORY_ID"

for path in $BPTR_INPUT_PATH; do
	if [ ! -e "$path" ]
	then
		echo "?? The given path does not exist: $path"
		echo "?? To resolve this issue, set the 'path' parameter to the location of your XML test report(s)."
		exit 1
	fi
done
REPORT_PATH="${BPTR_INPUT_PATH}"

echo "3. path: $REPORT_PATH"

if [ ! -d "$BPTR_INPUT_REPOSITORY_PATH" ]
then
	echo "?? The given path is not a directory: ${BPTR_INPUT_REPOSITORY_PATH}"
	echo "?? To resolve this issue, set the 'repository-path' parameter to the directory that contains the local git clone of your repository."
	exit 1
fi

# >>>>>> additional input replace START <<<<<<
REPOSITORY_PATH="${OPTIONAL_BPTR_INPUT_REPOSITORY_PATH}"
# from the user received INPUT_REPOSITORY_PATH value empty scenario read INPUT_REPOSITORY_PATH value from environment variable.
if [ -z "$OPTIONAL_BPTR_INPUT_REPOSITORY_PATH" ]
then
    REPOSITORY_PATH="${BPTR_INPUT_REPOSITORY_PATH}"
fi

COMMIT_SHA="${OPTIONAL_BPTR_INPUT_COMMIT}"
# from the user received INPUT_COMMIT value empty scenario read INPUT_COMMIT value from environment variable.
if [ -z "$OPTIONAL_BPTR_INPUT_COMMIT" ]
then
    COMMIT_SHA="${BPTR_INPUT_COMMIT:-$GITHUB_SHA}"
fi

# >>>>>> additional input replace END <<<<<<

#echo "4. key: $BPTR_INPUT_KEY" 
#echo "5. secret: $BPTR_INPUT_SECRET"
echo "4. key: ***" 
echo "5. secret: ***"
echo "6. repository path: $REPOSITORY_PATH"
echo "7. commit sha: $COMMIT_SHA"

if test -z "$BPTR_INPUT_KEY" && test -z "$BPTR_INPUT_SECRET" && test "$GITHUB_ACTOR" = "dependabot[bot]"
then
	echo "::warning ::No value available for the 'key' parameter or the 'secret' parameter. Skipping upload to BuildPulse."
	echo "?? ?? ?? As of March 1, 2021, Dependabot PRs cannot access secrets in GitHub Actions. See details on the GitHub blog at https://bit.ly/3KAoIBf"
	echo "?? ?? ?? Secrets are necessary in order to authenticate with external services like BuildPulse."
	echo "?? ?? ?? Since secrets aren't available in this build, the build cannot authenticate with BuildPulse to upload test results."
	exit 0
fi

echo "8. operating system: $BPTR_RUNNER_OS"

case "$BPTR_RUNNER_OS" in
	Linux)
		BUILDPULSE_TEST_REPORTER_BINARY=test-reporter-linux-amd64
		;;
	macOS)
		BUILDPULSE_TEST_REPORTER_BINARY=test-reporter-darwin-amd64
		;;
	Windows)
		BUILDPULSE_TEST_REPORTER_BINARY=test-reporter-windows-amd64.exe
		;;
	*)
		echo "::error::Unrecognized operating system. Expected RUNNER_OS to be one of \"Linux\", \"macOS\", or \"Windows\", but it was \"$RUNNER_OS\"."
		exit 1
esac

BUILDPULSE_TEST_REPORTER_HOSTS=(
	https://get.buildpulse.io
	https://github.com/buildpulse/test-reporter/releases/latest/download
)
[ -n "${INPUT_CLI_HOST}" ] && BUILDPULSE_TEST_REPORTER_HOSTS=("${INPUT_CLI_HOST}" "${BUILDPULSE_TEST_REPORTER_HOSTS[@]}")

getcli() {
	local rval=-1
	for host in "${BUILDPULSE_TEST_REPORTER_HOSTS[@]}"; do
		url="${host}/${BUILDPULSE_TEST_REPORTER_BINARY}"
		if (set -x; curl -fsSL --retry 3 --retry-connrefused --connect-timeout 5 "$url" > "$1"); then
			return 0
		else
			rval=$?
		fi
	done;

	return $rval
}

if getcli ./buildpulse-test-reporter; then
	: # Successfully fetched binary. Great!
   echo " report tool download success...."
else
   echo " report tool download issue...."
	msg=$(cat <<-eos
		::warning::Unable to send test results to BuildPulse. See details below.

		Downloading the BuildPulse test-reporter failed with status $?.

		We never want BuildPulse to make your builds unstable. Since we're having
		trouble downloading the BuildPulse test-reporter, we're skipping the
		BuildPulse analysis for this build.

		If you continue seeing this problem, please get in touch at
		https://buildpulse.io/contact so we can look into this issue.
	eos
	)

	echo "${msg//$'\n'/%0A}" # Replace newlines with URL-encoded newlines for proper formatting in GitHub Actions annotations (https://github.com/actions/toolkit/issues/193#issuecomment-605394935)
	exit 0
fi

chmod +x ./buildpulse-test-reporter

set -x

BUILDPULSE_ACCESS_KEY_ID="${BPTR_INPUT_KEY}" \
	BUILDPULSE_SECRET_ACCESS_KEY="${BPTR_INPUT_SECRET}" \
	GITHUB_SHA="${COMMIT_SHA}" \
	BUILDPULSE_BUCKET="${BPTR_BUILDPULSE_BUCKET}" \
	./buildpulse-test-reporter submit $REPORT_PATH --account-id $ACCOUNT_ID --repository-id $REPOSITORY_ID --repository-dir "${REPOSITORY_PATH}"

