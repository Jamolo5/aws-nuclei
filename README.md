# AWS Public Endpoint Vulnerability Scanner

This is a learning project.
The goal is to create a tool which can scan an AWS account for any publicly available endpoints and perform a scan against said endpoints with the tool Nuclei

## Crawler

This is the part of the application which crawls the AWS account, scanning for deployed resources and gathering any publicly available endpoints. These are then published to an SQS queue for the Scanner to pick up and scan

## Scanner

This is the part of the application which runs Nuclei. Events from the SQS queue contain endpoints for Nuclei to scan. Any vulnerabilities found are written to the RDS Vulnerability Database

## Vulnerability Database

Single table database which contains all the vulnerabilities picked up by the Scanner.

This includes;
- CVE (or name of vulnerability)
- Severity
- Timestamp of discovery
- IP address of the vulnerable asset