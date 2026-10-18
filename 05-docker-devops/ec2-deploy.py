#!/usr/bin/env python3
"""ec2-deploy.py — boto3 mini-deploy: launch one or more EC2 instances from the CLI.

Purpose
-------
A small, readable example of using boto3 to launch t2.micro (or other) EC2
instances from command-line arguments, then report their instance IDs and
public IPs. Supports a real AWS dry-run so you can validate permissions and
parameters without actually launching anything.

Safety contract (same as the shell tools)
-----------------------------------------
  * A real launch costs money, so it asks y/N first. --yes or ASSUME_YES=1
    skips the prompt; a closed stdin counts as "no".
  * DRY_RUN=1 behaves like --dry-run: AWS validates the request and nothing
    is launched.
  * -h works without boto3 installed.

Prerequisites
-------------
  * Python 3.8+
  * boto3 installed:            pip install -r requirements.txt
  * AWS credentials configured: aws configure   (or env vars / instance role)
  * IAM permissions:            ec2:RunInstances, ec2:CreateTags,
                                ec2:DescribeInstances

Example
-------
  ./ec2-deploy.py --image-id ami-0abcdef1234567890 --key-name my-key \\
                  --tag web-01 --region us-east-1
  ./ec2-deploy.py --image-id ami-0abcdef1234567890 --dry-run
"""

from __future__ import annotations

import argparse
import os
import sys
from typing import List, Optional


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    """Parse and return command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Launch EC2 instances from CLI arguments using boto3.",
    )
    parser.add_argument(
        "--image-id",
        required=True,
        help="AMI image id to launch, e.g. ami-0abcdef1234567890 (required)",
    )
    parser.add_argument(
        "--key-name",
        default=None,
        help="name of an existing EC2 key pair for SSH access",
    )
    parser.add_argument(
        "--instance-type",
        default="t2.micro",
        help="EC2 instance type (default: t2.micro)",
    )
    parser.add_argument(
        "--count",
        type=int,
        default=1,
        help="number of instances to launch (default: 1)",
    )
    parser.add_argument(
        "--region",
        default=None,
        help="AWS region; defaults to your environment/profile setting",
    )
    parser.add_argument(
        "--tag",
        dest="name_tag",
        default=None,
        metavar="NAME",
        help="value for the instance 'Name' tag",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="ask AWS to validate the request without launching anything "
             "(also: DRY_RUN=1)",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="skip the confirmation before a real launch (also: ASSUME_YES=1)",
    )
    args = parser.parse_args(argv)

    if args.count < 1:
        parser.error("--count must be a positive integer")

    # The same environment toggles as the shell tools (lib/common.sh).
    if os.environ.get("DRY_RUN") == "1":
        args.dry_run = True
    if os.environ.get("ASSUME_YES") == "1":
        args.yes = True

    return args


def confirm_launch(args: argparse.Namespace) -> bool:
    """Ask before a real launch, because it starts billing. Dry runs never ask."""
    if args.dry_run or args.yes:
        return True
    where = f" in {args.region}" if args.region else ""
    try:
        reply = input(
            f"Launch {args.count} x {args.instance_type} from {args.image_id}{where}? "
            "This starts billing. [y/N] "
        )
    except EOFError:  # no terminal (cron, CI, a pipe): never assume yes
        print()
        return False
    return reply.strip().lower() in ("y", "yes")


def build_tag_spec(name_tag: Optional[str]) -> List[dict]:
    """Return a TagSpecifications list for the Name tag, or empty if unset."""
    if not name_tag:
        return []
    return [
        {
            "ResourceType": "instance",
            "Tags": [{"Key": "Name", "Value": name_tag}],
        }
    ]


def launch(args: argparse.Namespace) -> int:
    """Launch the instances and report results. Returns a process exit code."""
    # Imported here, not at the top, so -h and the tests work without boto3.
    try:
        import boto3
        from botocore.exceptions import (
            BotoCoreError,
            ClientError,
            NoCredentialsError,
            NoRegionError,
        )
    except ImportError:
        sys.stderr.write(
            "error: boto3 is not installed.\n"
            "       install it with:  pip install -r 05-docker-devops/requirements.txt\n"
        )
        return 1

    run_kwargs: dict = {
        "ImageId": args.image_id,
        "InstanceType": args.instance_type,
        "MinCount": args.count,
        "MaxCount": args.count,
        "DryRun": args.dry_run,
    }
    if args.key_name:
        run_kwargs["KeyName"] = args.key_name

    tag_spec = build_tag_spec(args.name_tag)
    if tag_spec:
        run_kwargs["TagSpecifications"] = tag_spec

    try:
        ec2 = boto3.resource("ec2", region_name=args.region)
        instances = ec2.create_instances(**run_kwargs)
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "")
        if code == "DryRunOperation":
            # AWS confirms the request would have succeeded.
            print("dry-run succeeded: the request is valid and would launch "
                  f"{args.count} {args.instance_type} instance(s).")
            return 0
        if code == "UnauthorizedOperation":
            sys.stderr.write(
                "error: your IAM identity lacks permission to run instances "
                "(need ec2:RunInstances).\n"
            )
            return 1
        sys.stderr.write(f"error: AWS rejected the request: {exc}\n")
        return 1
    except NoRegionError:
        sys.stderr.write("error: no AWS region set: pass --region or set AWS_DEFAULT_REGION\n")
        return 1
    except NoCredentialsError:
        sys.stderr.write("error: no AWS credentials found: run `aws configure` or set AWS_PROFILE\n")
        return 1
    except BotoCoreError as exc:
        sys.stderr.write(f"error: could not reach AWS: {exc}\n")
        return 1

    ids = [inst.id for inst in instances]
    print(f"launched {len(ids)} instance(s): {', '.join(ids)}")
    print("waiting for instances to enter the 'running' state...")

    failed = False
    for inst in instances:
        try:
            inst.wait_until_running()
            inst.reload()
            public_ip = inst.public_ip_address or "(none yet)"
            print(f"  {inst.id}  state={inst.state['Name']}  public-ip={public_ip}")
        except (ClientError, BotoCoreError) as exc:
            sys.stderr.write(f"  {inst.id}: could not fetch status: {exc}\n")
            failed = True

    return 1 if failed else 0


def main(argv: Optional[List[str]] = None) -> int:
    """Entry point. Returns the process exit code."""
    args = parse_args(argv)
    if not confirm_launch(args):
        sys.stderr.write("aborted: nothing was launched\n")
        return 1
    return launch(args)


if __name__ == "__main__":
    sys.exit(main())
