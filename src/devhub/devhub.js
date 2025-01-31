// Code powering "developer dashboard" aka devhub, at <https://tigerbeetle.github.io/tigerbeetle>.
//
// At the moment, it isn't clear what's the right style for this kind of non-Zig developer facing
// code, so the following is somewhat arbitrary:
//
// - camelCase naming
// - `deno fmt` for style
// - no TypeScript, no build step

window.onload = () =>
  Promise.all([
    mainReleaseRotation(),
    mainSeeds(),
    mainMetrics(),
  ]);

function assert(condition) {
  if (!condition) {
    alert("Assertion failed");
    throw "Assertion failed";
  }
}

function mainReleaseRotation() {
  const releaseManager = getReleaseManager();
  for (const week of ["previous", "current", "next"]) {
    document.querySelector(`#release-${week}`).textContent =
      releaseManager[week];
  }

  function getReleaseManager() {
    const week = getWeek(new Date());
    const candidates = [
      "batiati",
      "cb22",
      "chaitanyabhandari",
      "fabioarnold",
      "matklad",
      "sentientwaffle",
    ];
    candidates.sort();

    return {
      previous: candidates[week % candidates.length],
      current: candidates[(week + 1) % candidates.length],
      next: candidates[(week + 2) % candidates.length],
    };
  }
}

async function mainSeeds() {
  const dataUrl =
    "https://raw.githubusercontent.com/tigerbeetle/devhubdb/main/fuzzing/data.json";
  const issuesURL =
    "https://api.github.com/repos/tigerbeetle/tigerbeetle/issues?per_page=200";

  const [records, issues] = await Promise.all([
    (async () => await (await fetch(dataUrl)).json())(),
    (async () => await (await fetch(issuesURL)).json())(),
  ]);

  const pulls = issues.filter((issue) => issue.pull_request);
  const pullsByURL = new Map(
    pulls.map((pull) => [pull.pull_request.html_url, pull]),
  );
  const openPullRequests = new Set(pulls.map((it) => it.number));
  const untriagedIssues = issues.filter((issue) =>
    !issue.pull_request &&
    !issue.labels.map((label) => label.name).includes("triaged")
  );
  document.querySelector("#untriaged-issues-count").innerText =
    untriagedIssues.length;
  if (untriagedIssues.length) {
    document.querySelector("#untriaged-issues-count").classList.add("untriaged");
  }

  // Filtering:
  // - By default, show one seed per fuzzer per commit; exclude successes for the main branch and
  //   already merged pull requests.
  // - Clicking on the fuzzer cell in the table shows all seeds for this fuzzer/commit pair.
  // - "show all" link (in the .html) disables filtering completely.
  const query = new URLSearchParams(document.location.search);
  const query_fuzzer = query.get("fuzzer");
  const query_commit = query.get("commit");
  const query_all = query.get("all") !== null;
  const fuzzersWithFailures = new Set();

  const tableDom = document.querySelector("#seeds>tbody");
  let commit_previous = undefined;
  let seedFailCount = 0;

  for (const record of records) {
    let include = undefined;
    if (query_all) {
      include = true;
    } else if (query_fuzzer || query_commit) {
      include = (!query_fuzzer || record.fuzzer == query_fuzzer) &&
        (!query_commit || record.commit_sha == query_commit);
    } else if (
      pullRequestNumber(record) &&
      !openPullRequests.has(pullRequestNumber(record))
    ) {
      include = false;
    } else {
      include = (!record.ok || pullRequestNumber(record) !== undefined) &&
        !fuzzersWithFailures.has(record.branch + record.fuzzer);
      if (include) fuzzersWithFailures.add(record.branch + record.fuzzer);
    }

    if (!include) continue;

    const seedDuration = formatDuration(
      (record.seed_timestamp_end - record.seed_timestamp_start) * 1000,
    );
    const seedFreshness = formatDuration(
      Date.now() - (record.seed_timestamp_start * 1000),
    );
    const rowDom = document.createElement("tr");

    const seedSuccess = record.fuzzer === "canary" ? !record.ok : record.ok;
    if (seedSuccess) {
      rowDom.classList.add("success");
    } else {
      seedFailCount++;
    }
    if (record.commit_sha != commit_previous) {
      commit_previous = record.commit_sha;
      rowDom.classList.add("group-start");
    }

    const pull = pullsByURL.get(record.branch);
    const prLink = pullRequestNumber(record)
      ? `<a href="${record.branch}">#${pullRequestNumber(record)}</a>`
      : "";
    rowDom.innerHTML = `
          <td>
            <a href="https://github.com/tigerbeetle/tigerbeetle/commit/${record.commit_sha}" class="seed-commit">
              ${record.commit_sha.substring(0, 7)}
            </a>
            ${prLink}
          </td>
          <td>${pull ? pull.user.login : ""}</td>
          <td><a href="?fuzzer=${record.fuzzer}&commit=${record.commit_sha}">${record.fuzzer}</a></td>
          <td><code>${record.command}</code></td>
          <td><time>${seedDuration}</time></td>
          <td><time>${seedFreshness} ago</time></td>
          <td>${record.count}</td>
      `;
    tableDom.appendChild(rowDom);
  }

  let mainBranchFail = 0;
  let mainBranchOk = 0;
  let mainBranchCanary = 0;
  for (const record of records) {
    if (record.branch == "https://github.com/tigerbeetle/tigerbeetle") {
      if (record.fuzzer === "canary") {
        mainBranchCanary += record.count;
      } else if (record.ok) {
        mainBranchOk += record.count;
      } else {
        mainBranchFail += record.count;
      }
    }
  }
  if (mainBranchFail > 0 && !query_commit && !query_fuzzer) {
    // When there are failures on main and we don't query for a specific commit/fuzzer,
    // there should be failing seeds in our table.
    assert(seedFailCount > 0);
  }
}

async function mainMetrics() {
  const dataUrl =
    "https://raw.githubusercontent.com/tigerbeetle/devhubdb/main/devhub/data.json";
  const data = await (await fetch(dataUrl)).text();
  const maxBatches = 200;
  const batches = data.split("\n")
    .filter((it) => it.length > 0)
    .map((it) => JSON.parse(it))
    .slice(-1 * maxBatches)
    .reverse();

  const series = batchesToSeries(batches);
  plotSeries(series, document.querySelector("#charts"), batches.length);
}

function pullRequestNumber(record) {
  const prPrefix = "https://github.com/tigerbeetle/tigerbeetle/pull/";
  if (record.branch.startsWith(prPrefix)) {
    const prNumber = record.branch.substring(
      prPrefix.length,
      record.branch.length,
    );
    return parseInt(prNumber, 10);
  }
  return undefined;
}

function formatDuration(durationInMilliseconds) {
  const milliseconds = durationInMilliseconds % 1000;
  const seconds = Math.floor((durationInMilliseconds / 1000) % 60);
  const minutes = Math.floor((durationInMilliseconds / (1000 * 60)) % 60);
  const hours = Math.floor((durationInMilliseconds / (1000 * 60 * 60)) % 24);
  const days = Math.floor(durationInMilliseconds / (1000 * 60 * 60 * 24));
  const parts = [];

  if (days > 0) {
    parts.push(`${days}d`);
  }
  if (hours > 0) {
    parts.push(`${hours}h`);
  }
  if (minutes > 0) {
    parts.push(`${minutes}m`);
  }
  if (days == 0) {
    if (seconds > 0 || parts.length === 0) {
      parts.push(`${seconds}s`);
    }
    if (hours == 0 && minutes == 0) {
      if (milliseconds > 0) {
        parts.push(`${milliseconds}ms`);
      }
    }
  }

  return parts.join(" ");
}

// Returns the ISO week of the date.
//
// Source: https://weeknumber.com/how-to/javascript
function getWeek(date) {
  date = new Date(date.getTime());
  date.setHours(0, 0, 0, 0);
  // Thursday in current week decides the year.
  date.setDate(date.getDate() + 3 - (date.getDay() + 6) % 7);
  // January 4 is always in week 1.
  const week1 = new Date(date.getFullYear(), 0, 4);
  // Adjust to Thursday in week 1 and count number of weeks from date to week1.
  return 1 + Math.round(
    ((date.getTime() - week1.getTime()) / 86400000 -
      3 + (week1.getDay() + 6) % 7) / 7,
  );
}

// The input data is array of runs, where a single run contains many measurements (eg, file size,
// build time).
//
// This function "transposes" the data, such that measurements with identical labels are merged to
// form a single array which is what we want to plot.
//
// This doesn't depend on particular plotting library though.
function batchesToSeries(batches) {
  const results = new Map();
  for (const [index, batch] of batches.entries()) {
    for (const metric of batch.metrics) {
      if (!results.has(metric.name)) {
        results.set(metric.name, {
          name: metric.name,
          unit: undefined,
          value: [],
          git_commit: [],
          timestamp: [],
        });
      }

      const series = results.get(metric.name);
      assert(series.name == metric.name);

      if (series.unit) {
        assert(series.unit == metric.unit);
      } else {
        series.unit = metric.unit;
      }

      // Even though our x-axis is time, we want to spread things out evenly by batch, rather than
      // group according to time. Apex charts is much quicker when given an x value, even though it
      // isn't strictly needed.
      series.value.push([batches.length - index, metric.value]);
      series.git_commit.push(batch.attributes.git_commit);
      series.timestamp.push(batch.timestamp);
    }
  }

  return results;
}

// Plot time series using <https://apexcharts.com>.
function plotSeries(seriesList, rootNode, batchCount) {
  for (const series of seriesList.values()) {
    let options = {
      title: {
        text: series.name,
      },
      chart: {
        type: "line",
        height: "400px",
        animations: {
          enabled: false,
        },
        events: {
          dataPointSelection: (event, chartContext, { dataPointIndex }) => {
            window.open(
              "https://github.com/tigerbeetle/tigerbeetle/commit/" +
                series.git_commit[dataPointIndex],
            );
          },
        },
      },
      markers: {
        size: 4,
      },
      series: [{
        name: series.name,
        data: series.value,
      }],
      xaxis: {
        categories: Array(series.value[series.value.length - 1][0]).fill("")
          .concat(
            series.timestamp.map((timestamp) =>
              formatDateDay(new Date(timestamp * 1000))
            ).reverse(),
          ),
        min: 0,
        max: batchCount,
        tickAmount: 15,
        axisTicks: {
          show: false,
        },
        tooltip: {
          enabled: false,
        },
      },
      tooltip: {
        enabled: true,
        shared: false,
        intersect: true,
        x: {
          formatter: function (val, { dataPointIndex }) {
            const formattedDate = formatDateDayTime(
              new Date(series.timestamp[dataPointIndex] * 1000),
            );
            return `<div>${
              series.git_commit[dataPointIndex]
            }</div><div>${formattedDate}</div>`;
          },
        },
      },
    };

    if (series.unit === "bytes") {
      options.yaxis = {
        labels: {
          formatter: formatBytes,
        },
      };
    }

    if (series.unit === "ms") {
      options.yaxis = {
        labels: {
          formatter: formatDuration,
        },
      };
    }

    const div = document.createElement("div");
    rootNode.append(div);
    const chart = new ApexCharts(div, options);
    chart.render();
  }
}

function formatBytes(bytes) {
  if (bytes === 0) return "0 Bytes";

  const k = 1024;
  const sizes = [
    "Bytes",
    "KiB",
    "MiB",
    "GiB",
    "TiB",
    "PiB",
    "EiB",
    "ZiB",
    "YiB",
  ];

  let i = 0;
  while (i != sizes.length - 1 && Math.pow(k, i + 1) < bytes) {
    i += 1;
  }

  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + " " + sizes[i];
}

function formatDateDay(date) {
  return formatDate(date, false);
}

function formatDateDayTime(date) {
  return formatDate(date, true);
}

function formatDate(date, include_time) {
  assert(date instanceof Date);

  const pad = (number) => String(number).padStart(2, "0");

  const year = date.getFullYear();
  const month = pad(date.getMonth() + 1); // Months are 0-based.
  const day = pad(date.getDate());
  const hours = pad(date.getHours());
  const minutes = pad(date.getMinutes());
  const seconds = pad(date.getSeconds());
  return include_time
    ? `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`
    : `${year}-${month}-${day}`;
}
