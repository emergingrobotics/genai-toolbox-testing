# Python Agent for MCP Toolbox

A Python agent that connects Amazon Bedrock (Claude) to the MCP Toolbox server, providing a chat interface with database tool access.

## Prerequisites

- Python 3.10+
- [uv](https://docs.astral.sh/uv/) package manager
- AWS account with Bedrock access enabled
- AWS credentials configured
- MCP Toolbox server running

## Installation

```bash
uv sync
```

Or install dependencies directly:

```bash
uv pip install -r requirements.txt
```

## Usage

1. Start the MCP Toolbox server:
   ```bash
   ../server/scripts/run.sh
   ```

2. Run the agent:
   ```bash
   uv run python agent.py
   ```

3. Chat with your database:
   ```
   You: What tables are in the database?
   You: How many rows are in the CarReport table?
   You: quit
   ```

## Configuration

Set environment variables to customize:

| Variable | Description | Default |
|----------|-------------|---------|
| `MCP_URL` | MCP Toolbox SSE endpoint | `http://localhost:5001/mcp/sse` |
| `BEDROCK_MODEL_ID` | Claude model to use | `anthropic.claude-sonnet-4-5-20250929-v1:0` |
| `AWS_REGION` | AWS region for Bedrock | `us-east-1` |

Example:
```bash
AWS_REGION=us-west-2 BEDROCK_MODEL_ID=anthropic.claude-haiku-4-5-20251001-v1:0 uv run python agent.py
```

## Commands

- Type your question and press Enter
- `clear` - Reset conversation history
- `quit` - Exit the agent

## More Information

See [docs/python-agent.md](../docs/python-agent.md) for detailed documentation.
