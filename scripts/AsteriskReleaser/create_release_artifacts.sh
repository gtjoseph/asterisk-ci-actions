#!/bin/bash
set -e

declare needs=( end_tag )
declare wants=( src_repo dst_dir security norc alembic
				changelog commit tag push tarball patchfile
				close_issues sign full_monty dry_run )
declare tests=( src_repo dst_dir )

progdir="$(dirname $(realpath $0) )"
source "${progdir}/common.sh"

declare -A end_tag
tag_parser ${END_TAG} end_tag || bail "Unable to parse end tag '${END_TAG}'"
${DEBUG} && declare -p end_tag

if [ -z "${START_TAG}" ] ; then
	START_TAG=$($progdir/get_start_tag.sh \
		--end-tag=${END_TAG} --src-repo="${SRC_REPO}" \
		$(booloption security) $(booloption norc) $(booloption debug) )
fi
if [ -z "${START_TAG}" ] ; then
	bail "can't determine a start tag"
fi		

${ECHO_CMD} git -C "${SRC_REPO}" checkout ${end_tag[branch]}
cd "${SRC_REPO}"

if ${CHERRY_PICK} ; then
	if [ "${end_tag[release]}" != "-rc1" ] ; then
		debug "Automatic cherry-picking only needed when
		creating an rc1. Skipping."
	else
		commitlist=$(mktemp)
		${ECHO_CMD} git -C "${SRC_REPO}" cherry ${end_tag[branch]} ${end_tag[source_branch]} |\
			sed -n -r -e "s/^[+]\s?(.*)/\1/gp" > ${commitlist}
		commitcount=$(wc -l ${commitlist} | sed -n -r -e "s/([0-9]+).*/\1/gp")
		[ $commitcount -eq 0 ] && bail "There were no commits to cherry-pick"
		debug "Cherry picking $commitcount commit(s) from ${end_tag[source_branch]} to ${end_tag[branch]}"
		echo git -C "${SRC_REPO}" cherry-pick -x $(< ${commitlist})
		${ECHO_CMD} git -C "${SRC_REPO}" cherry-pick -x $(< ${commitlist})
		${ECHO_CMD} rm ${commitlist} &>/dev/null || :
		debug "Done"
	fi
fi

if ${ALEMBIC} ; then
	debug "Creating Alembic scripts for ${END_TAG}"
	$ECHO_CMD $progdir/create_alembic_scripts.sh \
		--start-tag=${START_TAG} --end-tag=${END_TAG} \
		--src-repo="${SRC_REPO}" --dst-dir="${DST_DIR}" \
		$(booloption debug)
fi

echo "${END_TAG}" > ${DST_DIR}/.version
if ${CHANGELOG} ; then
	debug "Creating ChangeLog for ${START_TAG} -> ${END_TAG}"
	$ECHO_CMD $progdir/create_changelog.sh --start-tag=${START_TAG} \
		--end-tag=${END_TAG} --src-repo="${SRC_REPO}" --dst-dir="${DST_DIR}" \
		$(booloption debug)
fi

if ${COMMIT} ; then
	${ALEMBIC} || ${CHANGELOG} || bail "There were no changes so so there's nothing to commit"
	debug "Committing changes for ${END_TAG}"
	$ECHO_CMD $progdir/commit_changes.sh --start-tag=${START_TAG} \
		--end-tag=${END_TAG} --src-repo="${SRC_REPO}" --dst-dir="${DST_DIR}" \
		$(booloption debug)
fi

if ${TAG} ; then
	${COMMIT} || bail "There was no commit so there's nothing to tag"
	debug "Creating tag for ${END_TAG}"
	$ECHO_CMD git -C "${SRC_REPO}" checkout ${end_tag[branch]}
	$ECHO_CMD git -C "${SRC_REPO}" tag -a ${END_TAG} -m ${END_TAG}
fi

if ${TARBALL} ; then
	debug "Creating tarball for ${END_TAG}"
	$ECHO_CMD $progdir/create_tarball.sh \
		--start-tag=${START_TAG} --end-tag=${END_TAG} \
		--src-repo="${SRC_REPO}" --dst-dir="${DST_DIR}" \
		$(booloption sign) $(booloption debug)
fi

if ${PATCHFILE} ; then
	debug "Creating patchfile for ${END_TAG}"
	$ECHO_CMD $progdir/create_patchfile.sh \
		--start-tag=${START_TAG} --end-tag=${END_TAG} \
		--src-repo="${SRC_REPO}" --dst-dir="${DST_DIR}" \
		$(booloption sign) $(booloption debug)
fi

if ${PUSH} ; then
	debug "Pushing commits upstream"
	$ECHO_CMD git -C "${SRC_REPO}" checkout ${end_tag[branch]}
	$ECHO_CMD git -C "${SRC_REPO}" push
	debug "Pushing tag upstream"
	$ECHO_CMD git -C "${SRC_REPO}" push origin ${END_TAG}:${END_TAG}
fi

if ${LABEL_ISSUES} ; then
	debug "Labelling closed issues for ${END_TAG}"
	$ECHO_CMD $progdir/label_issue s.sh \
		--start-tag=${START_TAG} --end-tag=${END_TAG} \
		--src-repo="${SRC_REPO}" --dst-dir="${DST_DIR}" \
		$(booloption debug)
fi

if ${PUSH_LIVE} ; then
	debug "Pushing Asterisk Release ${END_TAG} live"
	cd "${SRC_REPO}"
	RC=0
	$ECHO_CMD gh release create ${END_TAG} \
		--verify-tag \
		$( [ "${end_tag[release_type]}" != "ga" ] && echo "--prerelease" ) \
		--notes-file ${DST_DIR}/email_announcement.md \
		--target ${end_tag[branch]} -t "Asterisk Release ${END_TAG}" \
		${DST_DIR}/asterisk-${END_TAG}.* \
		${DST_DIR}/ChangeLog-${END_TAG}.md \
		${DST_DIR}/README-${END_TAG}.md || RC=1
	if [ $RC -eq 1 ] ; then
		$ECHO_CMD gh release create ${END_TAG} \
			--verify-tag \
			$( [ "${end_tag[release_type]}" != "ga" ] && echo "--prerelease" ) \
			--notes-file ${DST_DIR}/release_notes.md \
			--target ${end_tag[branch]} -t "Asterisk Release ${END_TAG}" \
			${DST_DIR}/asterisk-${END_TAG}.* \
			${DST_DIR}/ChangeLog-${END_TAG}.md \
			${DST_DIR}/README-${END_TAG}.md
	fi
fi

