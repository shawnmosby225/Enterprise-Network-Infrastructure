# Enterprise AWS Architecture with Automated DevSecOps Pipeline

A production-grade, secure multi-tier network architecture provisioned using Terraform and continuously orchestrated using GitHub Actions. This project demonstrates an active **"Shift-Left" security paradigm**, embedding automated Snyk Infrastructure-as-Code (IaC) compliance gates directly into the deployment engine to halt insecure modifications before they ever reach the cloud.

## Architectural Deep Dive & Data Flow

This project creates a hardened, isolated network environment designed around strict zero-trust enterprise constraints.

When designing enterprise cloud infrastructure, the primary goal is minimizing the blast radius of a potential attack. This architecture was specifically selected to solve the vulnerabilities common in naive single-tier or default cloud setups.

### 1. Multi-Tier Network Isolation (VPC & Subnets)
* **The Decision:** Splitting the network into an explicit public tier (`192.168.10.0/24`) and an isolated private tier (`192.168.20.0/24`).
* **The Justification:** In standard environments, database or application servers should never possess a direct route to or from the open internet. By placing a **NAT Gateway** in the public subnet, our application tier inside the private subnet can securely initiate outbound requests (for things like security patches) while remaining completely invisible to incoming external internet scans.

### 2. Zero-Trust Security Groups
* **The Decision:** Limiting egress rules strictly to ports `80` and `443` instead of standard open internet routing (`-1` protocol for all traffic to `0.0.0.0/0`).
* **The Justification:** If a malicious actor successfully compromises a web application via an exploit, their first move is typically to establish a reverse shell or exfiltrate databases to a command-and-control server. By clamping outbound access down exclusively to standard web-patching ports, we severely cripple an attacker's ability to exfiltrate raw data or communicate with non-standard malicious ports.

### 3. Compute Hardening Toggles
* **IMDSv2 Enforcement (`http_tokens = "required"`):** Traditional AWS instances allow the older Instance Metadata Service (IMDSv1), which is highly vulnerable to SSRF flaws. Enforcing IMDSv2 requires session-oriented token handshakes, which makes it harder for attackers to steal IAM instance roles.
* **KMS Storage Encryption (`encrypted = true`):** Ensures that the underlying physical storage media hosting the OS root volume (`gp3`) is fully encrypted at rest. If a drive is decommissioned or physically accessed within an AWS data center, the raw data remains unreadable.
* **API Termination Protection (`disable_api_termination = true`):** Acts as a crucial operational guardrail. It prevents scripts, rogue automated deletion processes, or fatigued engineers from accidentally purging production database or core application nodes via a single console click.

---

## File-by-File Technical Blueprint

### 1. `provider.tf`
Establishes the fundamental API handshake between Terraform and Amazon Web Services. It sets the cloud provider source to `hashicorp/aws` and defines the default AWS region (`us-east-1`) to ensure everything is handled within the same region.

### 2. `variables.tf`
Declares the input variables used throughout the workspace, such as the `vpc_cidr` (`192.168.0.0/16`) and the deployment region. This modularizes the code, allowing any operations team to clone this configuration and rapidly spin up duplicate environments simply by passing different variable files.

### 3. `vpc.tf`
*This file maps and creates the core AWS networking components:* 
* `aws_vpc.main`: sets up the isolated software-defined data center network block. 
* `aws_subnet.public_1` & `aws_subnet.private_1`: creates the subnets that seperate IP allocations for public traffic and isolates the private instances. 
* `aws_internet_gateway`: attaches an entry/exit point to the VPC, allowing the public subnet to be reached and communicate with the internet.
* `aws_eip` & `aws_nat_gateway`: creates a static, public Elastic IP address and binds it to a NAT Gateway device, enabling secure translation of private internal traffic to public web addresses.
* `aws_route_table` & `aws_route_table_association`: builds the routing tables that decide traffic behavior. This binds the public subnet to the Internet Gateway, and binds the private subnet's traffic to travel out through the NAT Gateway.

### 4. `compute.tf`
*Handles the provisioning of active infrastructure workloads and strict network access lists:*
* `data.aws_ami.ubuntu`: queries the live AWS catalog to discover and pull the latest verified, official Ubuntu 24.04 LTS (Noble Numbat) operating system image.
* `aws_security_group.app_sg`: creates the stateful distributed instance firewall. It handles inside-the-network mapping rules, explicitly limiting ingress to internal ranges on ports 22 and 80, and containing our zero-trust outbound rules.
* `aws_instance.app_server`: deploys the virtual machine itself, injecting it into the private subnet, disabling public IP allocation, locking down the metadata service to IMDSv2, and enforcing root disk volume encryption.

---

## Automated Pipeline Architecture

*The continuous integration engine is powered natively by GitHub Actions (`.github/workflows/devsecops.yml`). It functions via three sequential quality gates:*

1. **Gate 1: Lint & Validate (`validate` job):** Installs Terraform on a clean Ubuntu runner, verifies code styling conventions via `terraform fmt -check`, and runs `terraform validate` to confirm structural and syntax integrity.
2. **Gate 2: Shift-Left Security Gate (`security` job):** Invokes the official Snyk IaC scanner. It audits the raw state files before execution. If a developer attempts to weaken a firewall or unencrypt a disk, Snyk returns a non-zero exit code and halts the pipeline completely.
3. **Policy Exception Engine (`.snyk`):** Manages real-world governance. Outbound patching to `0.0.0.0/0` over ports 80/443 is deliberately authorized via an documented `.snyk` policy rule exception, demonstrating practical enterprise governance compliance.
4. **Gate 3: Cloud Execution Engine (`execution` job):** Dynamically evaluates inputs. It handles automated resource generation planning or triggers clean resource demolition based on operational demands.

---

## GitHub Actions Engine: Step-by-Step Pipeline Orchestration

*The configuration in `.github/workflows/devsecops.yml` completely automates infrastructure continuous integration through a highly optimized three-job lifecycle runner:*

### Job 1: Lint & Validate (`validate`)
* Installs the official HashiCorp Terraform CLI on an ephemeral Ubuntu cloud environment.
* Runs `terraform fmt -check`. This is the **linter stage**—it stops the pipeline if an engineer writes messy, poorly aligned, or non-standard code.
* Runs `terraform validate`, which verifies that the internal logical mapping, reference variables, and resource dependencies are structurally sound.

### Job 2: Snyk Security Scan (`security`)
* Pulls down the code and activates the native **Snyk IaC Scanner**.
* Integrates a hidden repository secret (`SNYK_TOKEN`) to authenticate our pipeline directly with the Snyk platform.
* Automatically references our local **`.snyk` governance policy file**, allowing explicit exceptions (like a port 80/443 public egress rule) to pass through with documented justifications.

### Job 3: Cloud Infrastructure Execution (`execution`)
* Utilizes a highly flexible `workflow_dispatch` design pattern to separate infrastructure deployment logic from resource destruction.
* **If a push or standard planning action occurs:** It safely runs `terraform plan`, generating a detailed output blueprint showing exactly what resources AWS *would* build, without altering live infrastructure.
* **If an explicit 'destroy' command is passed:** It leverages an isolated conditional fork to run `terraform destroy -auto-approve`, tearing down the cloud environment safely to maintain cost-efficiency.

---

## "Shift-Left" Security

*In traditional software deployment lifecycles, security reviews occur at the very end of the line. Usually they are done right before production release or even after code is live by manual auditing or penetration testing. If a dangerous misconfiguration is found (such as an unencrypted volume containing user data), operations teams must freeze releases, roll back code, and rewrite core systems at massive expense and risk.*

**This architecture shifts security entirely to the "left" (the earliest possible point in the development cycle):**

1. **Flaws Stopped Early in Production:** If an engineer accidentally deletes an encryption flag or opens a security group to `0.0.0.0/0` on all ports, the flaw is caught while it is still a text file in the source repository.
2. **Automated Quality Gates:** By embedding Snyk directly into GitHub Actions, compliance checking is removed from human interaction. The pipeline acts as a quality gate. This way code that violates enterprise policy is structurally blocked from ever running a `terraform plan` or connecting to an active AWS account.
3. **Drastic Risk Mitigation:** Security is transformed from a post-incident clean-up process into a proactive, automated software compiler rule. The cloud footprint remains fundamentally secure by default.

---

## 🚀 Step-by-Step Replication & Setup Guide

### Prerequisites
* An active **AWS Account** with administrative programmatic access.
* A free **Snyk Developer Account**.
* A **GitHub Account** with Git installed locally on your workstation.

### Step 1: Configure Secret Vaults
To allow GitHub Actions to safely talk to AWS and Snyk without leaking keys in code, you must inject your credentials into GitHub's encrypted secrets environment.

1. **Grab Snyk Token:** Log into Snyk ➔ Click your profile icon (bottom-left) ➔ **Account Settings** ➔ Copy your **Personal Access Token (PAT)**.
2. **Grab AWS Keys:** Log into AWS Console ➔ Navigate to **IAM** ➔ **Security Credentials** ➔ Generate a new **Access Key ID** and **Secret Access Key**.
3. **Inject to GitHub:** Go to your GitHub Repository ➔ **Settings** (gear icon) ➔ **Secrets and variables** ➔ **Actions** ➔ Click **New repository secret**. Add these three entries:
   * `SNYK_TOKEN` = *(Your Snyk PAT Token)*
   * `AWS_ACCESS_KEY_ID` = *(Your AWS Access Key ID)*
   * `AWS_SECRET_ACCESS_KEY` = *(Your AWS Secret Access Key)*

### Step 2: Link and Push to GitHub
Open your terminal inside your project root folder and execute the initialization sequence:

```
git init
git add .
git commit -m "feat: initial commit of hardened infra and automated pipeline"
git branch -M main
git remote add origin [https://github.com/YOUR_USERNAME/YOUR-REPO-NAME.git](https://github.com/YOUR_USERNAME/YOUR-REPO-NAME.git)
git push -u origin main
```

### Step 3: Watch the Pipeline do it's work
*At this point you can go to actions on your Github repository and see the pipeline go through the 3 jobs.*
1. Go to the **Actions** tab on your Github repostory page
2. Click on the running **"Enterprise DevSecOps Pipeline** workflow execution.
3. Watch the sequential jobs execute live. Once a run has completed successfully, all jobs will turn green and the log output will display the blueprintsof the AWS resources staged for deployment.

## Usage in Day to Day Operations & Engineering Workflows

*This system works as a modular tool that is designed to safely streamline standard infrastructure management cycles:*

**1. Modifying Infrastructure (Day-to-Day Development)**
**If a develper needs to modify network parameters (such as scaling up instances or modifying subnets):*
- They create a feature branch
- They then adjust the terraform files and submit a pull request to the `main` branch
- The Github Actions pipeline runs automatically on the pull request. Snyk audits the changes before any engineer approves the merge

**2. Manual Triggered Plans**
**If an operator needs to manually check for configuration drift against the real AWS state without pushing code changes:*
- The developer would first go to the **Actions** tab, then click on **"Enterprise DevSecOps Pipeline"**
- They would then click the gray **"Run workflow"** drop-down button on the right side.
- They would then select the `plan` option and click the green button. 
- The system would safely poll AWS and report any state discrepancies. 

**3. Automated Environment Teardown**
**To minimize costs during development or rapidly isolate a compromised staging environment, a developer can run an automated demolition of the cloud resources:*
- The developer would first go to the **Actions** tab, then click on **"Enterprise DevSecOps Pipeline"**
- They would then click the gray **"Run workflow"** drop-down button on the right side.
- They would change the action selection from `plan` to `destroy`, then click on **run workflow**. 
- The runner would bypass the planning phase, build a secure AWS tunnel, and completely tear down all resources.

