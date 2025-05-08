/** @typedef {'SUCCESS_ALL' | 'IN_PROGRESS' | 'FAILED_OR_UNKNOWN' | 'UNKNOWN'} CheckStatus */

module.exports = async ({ github, context }) => {
    const { owner, repo } = context.repo;
    const headSha = context.payload.workflow_run.head_sha;

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

        allRuns.push(...res.data.workflow_runs);

        if (res.data.workflow_runs.length < perPage) break;
    }

    if (allRuns.length === 0) {
        console.log("No workflow_runs found for head_sha:", headSha);
        return "UNKNOWN";
    }

    let aggregatedStatus = null;
    let allSuccess = true;

    for (const run of allRuns) {
        const { name, status, conclusion } = run;

        if (status !== "completed") {
            console.log(`⏳ ${name}: in progress`);
            aggregatedStatus = "IN_PROGRESS";
            break;
        }

        if (conclusion === "success" || conclusion === "skipped" || conclusion === "action_required") {
            console.log(`✅ ${name}: ${conclusion}`);
            continue;
        }

        if (conclusion === "failure" || conclusion === "timed_out") {
            console.log(`❌ ${name}: failed`);
        } else if (conclusion === "cancelled") {
            console.log(`🚫 ${name}: cancelled`);
        } else {
            console.log(`❓ ${name}: unknown conclusion "${conclusion}"`);
        }

        allSuccess = false;
    }

    if (!aggregatedStatus) {
        aggregatedStatus = allSuccess ? "SUCCESS_ALL" : "FAILED_OR_UNKNOWN";
    }

    console.log("Aggregated Status:", aggregatedStatus);
    return aggregatedStatus;
};
