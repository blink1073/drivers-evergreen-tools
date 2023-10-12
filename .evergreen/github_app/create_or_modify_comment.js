/**
 * Create or modify a GitHub comment using the mongodb-drivers-comment-bot.
 */
import "child_process"
import "fs";
import "process";
import { program } from 'commander';
import { App } from "octokit";

const appId = process.env['GITHUB_APP_ID'];
const privateKey = process.env['GITHUB_SECRET_KEY'].replace(/\\n/g, '\n');
if (appId == '' || privateKey == '') {
    console.log("Missing GitHub App auth information");
    process.exit(1)
}

// Handle cli.
program
  .version('1.0.0', '-v, --version')
  .usage('[OPTIONS]...')
  .requiredOption('-s, --source-path <path>', 'The source path of the repo.')
  .requiredOption('-m, --body-match <string>', 'The comment body to match')
  .requiredOption('-c, --comment-path <path>', 'The path to the comment body file')
  .parse(process.argv);

const options = program.opts();
const sourcePath = options.sourcePath;
const bodyMatch = options.bodyMatch;
const bodyText = fs.readFileSync(options.bodyPath, { encoding: 'utf8' });

// Inspect git checkout for information.
const output = child_process.execSync(' git remote get-url --push origin', { cwd: sourcePath, encoding: 'utf8' });
const [owner, repo] = output.trim().split('github.com')[1].slice(1).replace('.git', '').split('/');
const targetSha = child_process.execSync('git rev-parse HEAD', { cwd: sourcePath, encoding: 'utf8' }).trim();

// Set up the app.
const installId = process.env['GITHUB_APP_INSTALL_ID_' + owner.toUpperCase()];
if (installId == '') {
    console.log(`Missing install id for ${owner}`)
    process.exit(1)
}
const app = new App({ appId, privateKey });
const octokit = await app.getInstallationOctokit(installId);
const headers =  {
    "x-github-api-version": "2022-11-28",
};

// Find the matching pull request.
let issueNumber = -1;
let resp = await octokit.request("GET /repos/{owner}/{repo}/pulls?state=open&per_page=100", {
    owner,
    repo,
    headers
});
for (const pull of resp['data']) {
    if (pull['head']['sha'] == targetSha) {
        issueNumber = pull['number'];
    }
}
if (issueNumber == -1) {
    console.log(`Could not find matching pull request for sha ${targetSha}`)
    process.exit(1)
}

// Find a matching comment if it exists, and update it.
var found = false
resp = await octokit.request("GET /repos/{owner}/{repo}/issues/{issue_number}/comments", {
    owner,
    repo,
    issue_number: issueNumber,
    headers
});
resp.data.forEach(async (comment) => {
    if (comment.body.includes(bodyMatch)) {
        if (found) {
            return
        }
        found = true;
        await octokit.request("PATCH /repos/{owner}/{repo}/issues/comments/{comment_id}", {
            owner,
            repo,
            body: bodyText,
            comment_id: comment.id,
            headers
        });
    }
})

// Otherwise create a new comment.
if (!found) {
    await octokit.request("POST /repos/{owner}/{repo}/issues/{issue_number}/comments", {
        owner,
        repo,
        issue_number: issueNumber,
        body: bodyText,
        headers
    });
}