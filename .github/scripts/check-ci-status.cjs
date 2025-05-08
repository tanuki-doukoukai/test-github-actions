/** @typedef {'SUCCESS_ALL' | 'IN_PROGRESS' | 'FAILED_OR_UNKNOWN' | 'UNKNOWN'} CheckStatus */

const isSuccessConclusion = (conclusion) =>
    ["success", "skipped", "action_required"].includes(conclusion);

module.exports = async ({ github, context }) => {
    const { owner, repo } = context.repo;
    const headSha = context.payload.workflow_run.head_sha;

    const perPage = 100;
    const maxPages = 5;
    const allRuns = [];

    // 最大500件取得（5ページ分）
    for (let page = 1; page <= maxPages; page++) {
        const res = await github.rest.actions.listWorkflowRunsForRepo({
            owner,
            repo,
            head_sha: headSha,
            per_page: perPage,
            page,
        });

        const runs = res.data.workflow_runs ?? [];
        if (runs.length === 0) break;

        allRuns.push(...runs);
        if (runs.length < perPage) break;
    }

    if (allRuns.length === 0) {
        console.log(`📭 No workflow_runs found for head_sha: ${headSha}`);
        return "UNKNOWN";
    }

    let isAllSuccess = true;

    for (const { name, status, conclusion } of allRuns) {
        if (status !== "completed") {
            console.log(`⏳ ${name}: status=${status}`);
            return "IN_PROGRESS";
        }

        if (isSuccessConclusion(conclusion)) {
            console.log(`✅ ${name}: conclusion=${conclusion}`);
            continue;
        }

        console.log(`❌ ${name}: conclusion=${conclusion}`);
        isAllSuccess = false;
    }

    const aggregatedStatus = isAllSuccess ? "SUCCESS_ALL" : "FAILED_OR_UNKNOWN";
    console.log(`🧾 Aggregated status: ${aggregatedStatus}`);

    return aggregatedStatus;
};
