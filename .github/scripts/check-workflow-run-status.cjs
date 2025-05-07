/** @typedef {'SUCCESS_ALL' | 'IN_PROGRESS' | 'FAILED_AND_COMPLETED' | 'CANCELED' | 'UNKNOWN'} CheckStatus */

module.exports = async ({ github, context }) => {
    const { owner, repo } = context.repo;
    const headSha = context.payload.workflow_run.head_sha;
    const selfRunId = context.payload.workflow_run.id;

    const perPage = 100;
    const maxPages = 5;
    const allRuns = [];

    // 最新のworkflow_runを最大500件（5ページ分）まで取得してhead_sha一致分を収集
    for (let page = 1; page <= maxPages; page++) {
        const res = await github.rest.actions.listWorkflowRunsForRepo({
            owner,
            repo,
            head_sha: headSha,
            per_page: perPage,
            page,
        });

        if (!res.data.workflow_runs || res.data.workflow_runs.length === 0) break;

        allRuns.push(...matching);

        if (res.data.workflow_runs.length < perPage) break;
    }

    if (allRuns.length === 0) {
        console.log("No workflow_runs found for head_sha:", headSha);
        return "UNKNOWN";
    }

    /** @type {CheckStatus | null} */
    let aggregatedStatus = null;

    // 各workflow_runのstatusとconclusionを確認して、最初に見つかったものを返す
    for (const run of allRuns) {
        const { name, status, conclusion } = run;

        if (status !== "completed") {
            console.log(`⏳ ${name}: in progress`);
            aggregatedStatus = "IN_PROGRESS";
            break;
        }

        if (conclusion === "failure" || conclusion === "timed_out") {
            console.log(`❌ ${name}: failed`);
            aggregatedStatus = "FAILED_AND_COMPLETED";
            break;
        }

        if (conclusion === "cancelled") {
            console.log(`🚫 ${name}: cancelled`);
            aggregatedStatus = "CANCELED";
            break;
        }

        if (
            conclusion !== "success" &&
            conclusion !== "skipped" &&
            conclusion !== "action_required"
        ) {
            console.log(`❓ ${name}: unknown conclusion "${conclusion}"`);
            aggregatedStatus = "UNKNOWN";
            break;
        }

        console.log(`✅ ${name}: ${conclusion}`);
    }

    if (!aggregatedStatus) {
        aggregatedStatus = "SUCCESS_ALL";
    }

    console.log("Aggregated Status:", aggregatedStatus);
    return aggregatedStatus;
};
