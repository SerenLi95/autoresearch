# Run Karpathy's Autoresearch Today

### An AI runs experiments on your computer all night while you sleep. Here's how to set it up.

---

## Step 0: Can Your Computer Do This?

**You need one of these:**

- **A Windows or Linux PC with an NVIDIA graphics card** (like an RTX 3060, 4070, or 4090)
- **A Mac with an M1, M2, M3, or M4 chip** (any Mac bought since late 2020)

**To check on Windows:** Press the Windows key, type "Command Prompt", open it, type `nvidia-smi`, press Enter. If you see your GPU name, you're good.

**To check on Mac:** Click the Apple menu → About This Mac. Look for "Chip." If it says M1, M2, M3, or M4 (or any variant like M2 Pro, M3 Max), you're good. If it says Intel, this won't work.

**If you don't have either of these, stop here** — this project requires a powerful GPU to run.

---

## Step 1: Open Your Terminal

This is a text window where you type commands. Every computer has one.

- **Mac:** Press `Cmd + Space`, type **Terminal**, press Enter
- **Windows:** Press the Windows key, type **PowerShell**, press Enter
- **Linux:** Press `Ctrl + Alt + T`

You'll use this window for every step below.

---

## Step 2: Install Two Small Tools

**Install uv** (this handles Python and all dependencies automatically):

Mac/Linux:

curl -LsSf https://astral.sh/uv/install.sh | sh


Windows (PowerShell):

powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"


**Install Claude Code** (the AI agent that runs experiments for you — requires a Claude Pro or Max subscription at $20–100/month):

Mac/Linux:

curl -fsSL https://claude.ai/install.sh | bash


Windows (PowerShell):

irm https://claude.ai/install.ps1 | iex


**Now close your Terminal and open a fresh one.** This is essential — skip it and the next steps will fail.

> **Don't want to pay for Claude Code?** Download Cursor for free from cursor.com instead. It does the same job but with a visual interface rather than the Terminal. The rest of this guide still applies — you'll just use Cursor's chat panel instead of Claude Code.

---

## Step 3: Install Git (If You Don't Have It)

Git tracks all the experiments. Check if you already have it:


git --version


If you see a version number, skip ahead. If not:

- **Mac:** It will prompt you to install Xcode Command Line Tools — click Install
- **Windows:** Download from https://git-scm.com/download/win and run the installer (accept all defaults)
- **Linux:** `sudo apt install git`

---

## Step 4: Download the Project

**Mac users** — you need the Mac-compatible version:

cd ~/Desktop
git clone https://github.com/miolini/autoresearch-macos.git
cd autoresearch-macos


**Windows/Linux users** — you need the original:

cd ~/Desktop
git clone https://github.com/karpathy/autoresearch.git
cd autoresearch


> On Windows, replace `~/Desktop` with `%USERPROFILE%\Desktop`

---

## Step 5: Set Everything Up

Run these three commands one at a time:


uv sync

*(Installs Python and all packages. Takes a few minutes the first time.)*


uv run prepare.py

*(Downloads training data. Takes about 2 minutes. Only needed once.)*


uv run train.py

*(Runs one 5-minute test. If it finishes and shows a number next to "val_bpb" — you're ready.)*

**If you get a red error:** Copy the entire error message, paste it into claude.ai, and ask "What does this mean and how do I fix it?" You'll get a direct answer.

---

## Step 6: Let the AI Run All Night

Make sure you're in the project folder, then launch Claude Code:


claude


It will ask you to log in the first time — follow the browser prompt.

Once you see the Claude Code prompt, type this:


Hi have a look at program.md and let's kick off a new experiment! Let's do the setup first.


**That's it.** Claude will start reading the project, modifying the training code, running 5-minute experiments, keeping what works, discarding what doesn't, and repeating. Minimise the window and go to sleep.

You'll wake up to dozens of successful experiments and a smarter model than you started with.

> **Using Cursor instead?** Open the project folder in Cursor (File → Open Folder), then type the same message into Cursor's AI chat panel on the right side.

---

## Quick Answers

**What is val_bpb?** A score measuring how smart the model is. Lower = better.

**What is train.py?** The single file containing all the AI training code. The AI agent modifies this file during experiments.

**What is program.md?** Your instruction file for the AI agent. This is the only file you ever need to edit — it tells the agent what to try.

**Is the Mac version safe?** Yes. Karpathy links to it from his own project page. The developer (Artem Andreenko) has 167 public projects on GitHub and a years-long public track record. The fork announcement got 70,000+ views on X. The entire codebase is about 630 lines — you can read the whole thing in 20 minutes.

**How many experiments will it run overnight?** About 100 (roughly 12 per hour).

**Do most experiments succeed?** No. Most fail. That's normal. The agent automatically keeps the wins and throws away the losses. Out of 100 experiments, maybe 10–20 will be improvements.

**What does it cost?** The code is free. Claude Code requires Claude Pro ($20/month) or Max ($100/month). Cursor has a free tier if you run experiments manually.

---

## If Something Goes Wrong

| Problem | Fix |
|---|---|
| `command not found: uv` | Close Terminal, open a new one |
| `command not found: git` | Install git (see Step 3) |
| CUDA / GPU error (Windows/Linux) | Search YouTube: "install CUDA toolkit [your GPU]" |
| MPS / Metal error (Mac) | Make sure you downloaded the Mac fork, not the original |
| Out of memory | Your GPU needs more VRAM. The agent usually adapts automatically |
| Claude Code won't authenticate | You need a paid Claude subscription ($20/month minimum) |

---

**Links:**
Original (Windows/Linux): https://github.com/karpathy/autoresearch
Mac version: https://github.com/miolini/autoresearch-macos
Cursor: https://cursor.com
Claude Code: https://code.claude.com

---

*Total setup time: about 30 minutes. Then it runs by itself.*