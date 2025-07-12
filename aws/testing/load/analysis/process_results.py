#!/usr/bin/env python3
"""
Process and analyze Locust load test results
"""

import argparse
import json
import os
from datetime import datetime

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


def load_csv_data(file_path):
    """Load CSV data from Locust output."""
    try:
        return pd.read_csv(file_path)
    except Exception as e:
        print(f"Error loading CSV file: {e}")
        return None


def generate_summary(stats_df, distribution_df=None, history_df=None):
    """Generate summary statistics from the test results."""
    if stats_df is None:
        return {}

    # Calculate overall statistics
    total_requests = stats_df["Request Count"].sum()
    total_failures = stats_df["Failure Count"].sum()
    failure_rate = (total_failures / total_requests * 100) if total_requests > 0 else 0

    # Calculate response time statistics
    avg_response_time = stats_df["Average Response Time"].mean()
    median_response_time = stats_df["Median Response Time"].mean()
    p95_response_time = stats_df["95%"].mean()
    p99_response_time = stats_df["99%"].mean()
    max_response_time = stats_df["Max Response Time"].max()

    # Calculate throughput
    total_rps = stats_df["Requests/s"].sum()

    # Create summary dictionary
    summary = {
        "timestamp": datetime.now().isoformat(),
        "total_requests": int(total_requests),
        "total_failures": int(total_failures),
        "failure_rate": round(failure_rate, 2),
        "avg_response_time": round(avg_response_time, 2),
        "median_response_time": round(median_response_time, 2),
        "p95_response_time": round(p95_response_time, 2),
        "p99_response_time": round(p99_response_time, 2),
        "max_response_time": round(max_response_time, 2),
        "total_rps": round(total_rps, 2),
    }

    # Add endpoint-specific statistics
    endpoints = []
    for _, row in stats_df.iterrows():
        if row["Name"] == "Aggregated":
            continue

        endpoint = {
            "name": row["Name"],
            "request_count": int(row["Request Count"]),
            "failure_count": int(row["Failure Count"]),
            "failure_rate": round((row["Failure Count"] / row["Request Count"] * 100) if row["Request Count"] > 0 else 0, 2),
            "avg_response_time": round(row["Average Response Time"], 2),
            "median_response_time": round(row["Median Response Time"], 2),
            "p95_response_time": round(row["95%"], 2),
            "p99_response_time": round(row["99%"], 2),
            "max_response_time": round(row["Max Response Time"], 2),
            "rps": round(row["Requests/s"], 2),
        }
        endpoints.append(endpoint)

    summary["endpoints"] = endpoints

    # Add history data if available
    if history_df is not None:
        summary["history"] = {
            "timestamps": history_df["Timestamp"].tolist(),
            "users": history_df["User Count"].tolist(),
            "rps": history_df["Total RPS"].tolist(),
            "failures": history_df["Total Failures"].tolist(),
        }

    return summary


def create_visualizations(stats_df, distribution_df=None, history_df=None, output_dir=None):
    """Create visualizations from the test results."""
    if stats_df is None:
        return

    # Filter out the Aggregated row for better visualizations
    stats_df = stats_df[stats_df["Name"] != "Aggregated"]

    # Create output directory if it doesn't exist
    if output_dir and not os.path.exists(output_dir):
        os.makedirs(output_dir)

    # 1. Response time by endpoint
    plt.figure(figsize=(12, 8))
    plt.subplot(2, 2, 1)
    stats_df.sort_values("Average Response Time", ascending=False).plot.bar(
        x="Name", y="Average Response Time", ax=plt.gca()
    )
    plt.title("Average Response Time by Endpoint")
    plt.xticks(rotation=90)
    plt.tight_layout()

    # 2. Request count by endpoint
    plt.subplot(2, 2, 2)
    stats_df.sort_values("Request Count", ascending=False).plot.bar(
        x="Name", y="Request Count", ax=plt.gca()
    )
    plt.title("Request Count by Endpoint")
    plt.xticks(rotation=90)
    plt.tight_layout()

    # 3. Failure count by endpoint
    plt.subplot(2, 2, 3)
    stats_df.sort_values("Failure Count", ascending=False).plot.bar(
        x="Name", y="Failure Count", ax=plt.gca()
    )
    plt.title("Failure Count by Endpoint")
    plt.xticks(rotation=90)
    plt.tight_layout()

    # 4. Response time percentiles
    plt.subplot(2, 2, 4)
    df_melted = pd.melt(
        stats_df,
        id_vars=["Name"],
        value_vars=["Median Response Time", "95%", "99%"],
        var_name="Percentile",
        value_name="Response Time (ms)",
    )
    df_pivot = df_melted.pivot(
        index="Name", columns="Percentile", values="Response Time (ms)"
    )
    df_pivot.plot.bar(ax=plt.gca())
    plt.title("Response Time Percentiles by Endpoint")
    plt.xticks(rotation=90)
    plt.tight_layout()

    # Save the figure
    if output_dir:
        plt.savefig(
            os.path.join(output_dir, "endpoint_metrics.png"),
            dpi=300,
            bbox_inches="tight",
        )

    # If we have history data, create time series plots
    if history_df is not None:
        plt.figure(figsize=(12, 8))

        # 1. RPS over time
        plt.subplot(2, 2, 1)
        plt.plot(history_df["Timestamp"], history_df["Total RPS"])
        plt.title("Requests per Second Over Time")
        plt.xlabel("Time")
        plt.ylabel("Requests per Second")
        plt.xticks(rotation=45)
        plt.grid(True)
        plt.tight_layout()

        # 2. Response time over time
        plt.subplot(2, 2, 2)
        plt.plot(
            history_df["Timestamp"],
            history_df["Average Response Time"],
            label="Average",
        )
        plt.plot(
            history_df["Timestamp"],
            history_df["Median Response Time"],
            label="Median",
        )
        plt.title("Response Time Over Time")
        plt.xlabel("Time")
        plt.ylabel("Response Time (ms)")
        plt.legend()
        plt.xticks(rotation=45)
        plt.grid(True)
        plt.tight_layout()

        # 3. Users over time
        plt.subplot(2, 2, 3)
        plt.plot(history_df["Timestamp"], history_df["User Count"])
        plt.title("Number of Users Over Time")
        plt.xlabel("Time")
        plt.ylabel("Users")
        plt.xticks(rotation=45)
        plt.grid(True)
        plt.tight_layout()

        # 4. Failures over time
        plt.subplot(2, 2, 4)
        plt.plot(history_df["Timestamp"], history_df["Total Failures"])
        plt.title("Failures Over Time")
        plt.xlabel("Time")
        plt.ylabel("Failures")
        plt.xticks(rotation=45)
        plt.grid(True)
        plt.tight_layout()

        # Save the figure
        if output_dir:
            plt.savefig(
                os.path.join(output_dir, "time_series.png"),
                dpi=300,
                bbox_inches="tight",
            )

    # If we have distribution data, create distribution plots
    if distribution_df is not None:
        plt.figure(figsize=(12, 6))
        plt.hist(distribution_df["Response Time"], bins=50)
        plt.title("Response Time Distribution")
        plt.xlabel("Response Time (ms)")
        plt.ylabel("Frequency")
        plt.grid(True)
        plt.tight_layout()

        # Save the figure
        if output_dir:
            plt.savefig(
                os.path.join(output_dir, "response_time_distribution.png"),
                dpi=300,
                bbox_inches="tight",
            )

    plt.close("all")


def main():
    """Main function to process Locust test results."""
    parser = argparse.ArgumentParser(description="Process Locust test results")
    parser.add_argument(
        "--input-file",
        required=True,
        help="Input CSV file with Locust stats (stats.csv)",
    )
    parser.add_argument(
        "--distribution-file",
        help="Input CSV file with response time distribution (stats_distribution.csv)",
    )
    parser.add_argument(
        "--history-file", help="Input CSV file with history data (stats_history.csv)"
    )
    parser.add_argument(
        "--output-dir",
        default="./results",
        help="Output directory for processed results",
    )

    args = parser.parse_args()

    # Create output directory if it doesn't exist
    if not os.path.exists(args.output_dir):
        os.makedirs(args.output_dir)

    # Load data
    stats_df = load_csv_data(args.input_file)
    distribution_df = (
        load_csv_data(args.distribution_file) if args.distribution_file else None
    )
    history_df = load_csv_data(args.history_file) if args.history_file else None

    if stats_df is None:
        print(f"Error: Could not load stats file {args.input_file}")
        return

    # Generate summary
    summary = generate_summary(stats_df, distribution_df, history_df)

    # Save summary as JSON
    with open(os.path.join(args.output_dir, "summary.json"), "w") as f:
        json.dump(summary, f, indent=2)

    # Create visualizations
    create_visualizations(stats_df, distribution_df, history_df, args.output_dir)

    print(f"Results processed and saved to {args.output_dir}")


if __name__ == "__main__":
    main()
