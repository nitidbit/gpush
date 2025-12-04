#!/usr/bin/env node

import { readFileSync } from "fs";
import { request as httpsRequest } from "https";
import { request as httpRequest } from "http";
import { URL } from "url";

function detectFileType(coverage) {
  // JS coverage (vitest) has a "total" key with lines/branches/statements/functions
  if (coverage.total && coverage.total.lines && coverage.total.branches) {
    return "js";
  }
  // SimpleCov has test framework keys (e.g., "RSpec") with "coverage" and "timestamp"
  if (
    Object.keys(coverage).some(
      (key) => coverage[key].coverage && coverage[key].timestamp,
    )
  ) {
    return "ruby";
  }
  return "unknown";
}

function processJSCoverage(coverage, title = "JS") {
  const total = coverage.total;
  const linesPct = Math.round(total.lines.pct);
  const branchesPct = Math.round(total.branches.pct);
  console.log(`${title} Lines ${linesPct}%`);
  console.log(`${title} Branches ${branchesPct}%`);
  return { title, lines: linesPct, branches: branchesPct };
}

function processRubyCoverage(coverage, title = "Ruby") {
  // SimpleCov .resultset.json format has coverage data per test framework (e.g., "RSpec")
  const framework = Object.keys(coverage)[0];
  const frameworkData = coverage[framework];

  // Calculate line coverage from the coverage hash
  let totalLines = 0;
  let coveredLines = 0;
  let totalBranches = 0;
  let coveredBranches = 0;

  Object.values(frameworkData.coverage || {}).forEach((fileCoverage) => {
    if (fileCoverage.lines && Array.isArray(fileCoverage.lines)) {
      fileCoverage.lines.forEach((line) => {
        if (line !== null) {
          totalLines++;
          if (line > 0) coveredLines++;
        }
      });
    }
    if (fileCoverage.branches) {
      Object.values(fileCoverage.branches).forEach((branch) => {
        if (typeof branch === "object" && branch !== null) {
          // Branches are objects with :then and :else keys
          Object.values(branch).forEach((branchCount) => {
            if (typeof branchCount === "number") {
              totalBranches++;
              if (branchCount > 0) coveredBranches++;
            }
          });
        } else if (typeof branch === "number") {
          // Some branches might be direct numbers
          totalBranches++;
          if (branch > 0) coveredBranches++;
        }
      });
    }
  });

  const lineCoverage = totalLines > 0 ? (coveredLines / totalLines) * 100 : 0;
  const branchCoverage =
    totalBranches > 0 ? (coveredBranches / totalBranches) * 100 : 0;

  const linesPct = Math.round(lineCoverage);
  const branchesPct = Math.round(branchCoverage);
  console.log(`${title} Lines ${linesPct}%`);
  console.log(`${title} Branches ${branchesPct}%`);
  return {
    title,
    lines: linesPct,
    branches: branchesPct,
  };
}

async function sendToSlack(coverages, appName, webhookUrl) {
  // Build fixed-width table: calculate column widths for proper alignment
  const columns = coverages.flatMap(({ title }) => [
    { header: `${title.toUpperCase()} LINES`, value: null },
    { header: `${title.toUpperCase()} BRANCHES`, value: null },
  ]);

  // Calculate max width for each column
  const colWidths = columns.map((col, index) => {
    const coverageIndex = Math.floor(index / 2);
    const isLines = index % 2 === 0;
    const value = isLines
      ? `${coverages[coverageIndex].lines}%`
      : `${coverages[coverageIndex].branches}%`;
    return Math.max(col.header.length, value.length);
  });

  // Format with fixed-width columns
  const pad = (str, width) => str.padEnd(width);
  const headerRow = columns
    .map((col, i) => pad(col.header, colWidths[i]))
    .join("  ");
  const dataRow = coverages
    .flatMap(({ lines, branches }, coverageIndex) => [
      pad(`${lines}%`, colWidths[coverageIndex * 2]),
      pad(`${branches}%`, colWidths[coverageIndex * 2 + 1]),
    ])
    .join("  ");

  const blocks = [
    {
      type: "header",
      text: {
        type: "plain_text",
        text: appName,
      },
    },
    {
      type: "section",
      text: {
        type: "mrkdwn",
        text: `\`\`\`\n${headerRow}\n${dataRow}\n\`\`\``,
      },
    },
  ];

  const payload = JSON.stringify({ blocks });

  return new Promise((resolve, reject) => {
    const url = new URL(webhookUrl);
    const isHttps = url.protocol === "https:";
    const requestModule = isHttps ? httpsRequest : httpRequest;
    const defaultPort = isHttps ? 443 : 80;

    const options = {
      hostname: url.hostname,
      port: url.port || defaultPort,
      path: url.pathname + url.search,
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(payload),
      },
    };

    const req = requestModule(options, (res) => {
      // Consume response data to allow connection to close
      res.on("data", () => {});
      res.on("end", () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve();
        } else {
          reject(new Error(`Slack API error: ${res.statusCode}`));
        }
      });
    });

    req.on("error", reject);
    req.write(payload);
    req.end();
  });
}

// Process all provided arguments
// Format: [APP_NAME] [file1] [title1] [file2] [title2] ...
// APP_NAME is optional first argument (if first arg doesn't look like a file and next arg is a file)
// Title is optional - if the next arg after a file doesn't look like a file path, it's treated as a title
let args = process.argv.slice(2);
let appName = "App";
const files = [];

// Check if first arg is APP_NAME
// APP_NAME is detected if: first arg doesn't look like a file AND next arg exists and looks like a file
if (
  args.length > 1 &&
  !args[0].endsWith(".json") &&
  !args[0].endsWith(".resultset") &&
  (args[1].endsWith(".json") || args[1].endsWith(".resultset"))
) {
  appName = args[0];
  args = args.slice(1); // Remove APP_NAME from args
}

for (let i = 0; i < args.length; i++) {
  const arg = args[i];
  // Check if next arg exists and doesn't look like a file path (no .json extension)
  const nextArg = args[i + 1];
  const hasTitle =
    nextArg && !nextArg.endsWith(".json") && !nextArg.endsWith(".resultset");

  files.push({
    path: arg,
    title: hasTitle ? nextArg : undefined,
  });

  if (hasTitle) {
    i++; // Skip the title arg
  }
}

const coverages = [];

files.forEach(({ path: filePath, title }) => {
  try {
    const coverage = JSON.parse(readFileSync(filePath, "utf8"));
    const fileType = detectFileType(coverage);

    if (fileType === "js") {
      const result = processJSCoverage(coverage, title);
      coverages.push(result);
    } else if (fileType === "ruby") {
      const result = processRubyCoverage(coverage, title);
      coverages.push(result);
    } else {
      console.error(`Unknown coverage format in ${filePath}`);
    }
  } catch (error) {
    console.error(`Error processing ${filePath}: ${error.message}`);
  }
});

// Send to Slack if webhook URL is provided
const slackWebhookUrl = process.env.SLACK_COVERAGE_WEBHOOK_URL;

if (slackWebhookUrl && coverages.length > 0) {
  sendToSlack(coverages, appName, slackWebhookUrl)
    .then(() => {
      console.log("Coverage posted to Slack");
      process.exit(0);
    })
    .catch((error) => {
      console.error(`Failed to send to Slack: ${error.message}`);
      process.exit(1);
    });
} else {
  process.exit(0);
}
