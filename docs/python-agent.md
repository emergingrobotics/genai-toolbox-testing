# Building a Python Agent with Amazon Bedrock and MCP

This guide explains how to build a Python agent that connects to Amazon Bedrock (Claude) and the MCP Toolbox server, providing a general-purpose chat interface with database tool access.

## Overview

The agent will:
1. Connect to Amazon Bedrock to use Claude models
2. Connect to the MCP Toolbox server via SSE transport
3. Implement a chat loop that handles tool calling
4. Execute database queries through MCP tools

## Prerequisites

- Python 3.10+
- AWS account with Bedrock access enabled
- AWS credentials configured (`~/.aws/credentials` or environment variables)
- MCP Toolbox server running (see main README)

## Installation

```bash
pip install boto3 mcp httpx
```

## Architecture

```
┌─────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   User      │────▶│  Python Agent   │────▶│ Amazon Bedrock  │
│  (stdin)    │◀────│                 │◀────│    (Claude)     │
└─────────────┘     └────────┬────────┘     └─────────────────┘
                             │
                             │ MCP/SSE
                             ▼
                    ┌─────────────────┐     ┌─────────────────┐
                    │  MCP Toolbox    │────▶│   SQL Server    │
                    │    Server       │◀────│    Database     │
                    └─────────────────┘     └─────────────────┘
```

## Complete Implementation

### agent.py

```python
#!/usr/bin/env python3
"""
Python agent that connects Amazon Bedrock (Claude) to MCP Toolbox.
Provides a chat interface with database tool access.
"""

import asyncio
import json
import boto3
from contextlib import AsyncExitStack
from mcp import ClientSession
from mcp.client.sse import sse_client


class MCPToolboxAgent:
    """Agent that bridges Bedrock Claude with MCP Toolbox."""

    def __init__(
        self,
        mcp_url: str = "http://localhost:5001/mcp/sse",
        model_id: str = "anthropic.claude-sonnet-4-5-20250929-v1:0",
        region: str = "us-east-1",
    ):
        self.mcp_url = mcp_url
        self.model_id = model_id
        self.region = region
        self.exit_stack = AsyncExitStack()
        self.session: ClientSession = None
        self.bedrock = boto3.client("bedrock-runtime", region_name=region)
        self.tools = []
        self.messages = []

    async def connect(self):
        """Connect to the MCP server."""
        print(f"Connecting to MCP server at {self.mcp_url}...")
        streams = await self.exit_stack.enter_async_context(
            sse_client(url=self.mcp_url)
        )
        self.session = await self.exit_stack.enter_async_context(
            ClientSession(*streams)
        )
        await self.session.initialize()

        # Fetch available tools
        tools_response = await self.session.list_tools()
        self.tools = tools_response.tools
        print(f"Connected! Available tools: {[t.name for t in self.tools]}")

    async def disconnect(self):
        """Disconnect from the MCP server."""
        await self.exit_stack.aclose()

    def _format_tools_for_bedrock(self) -> dict:
        """Convert MCP tools to Bedrock tool config format."""
        tool_specs = []
        for tool in self.tools:
            tool_specs.append({
                "toolSpec": {
                    "name": tool.name,
                    "description": tool.description or "",
                    "inputSchema": {
                        "json": tool.inputSchema
                    }
                }
            })
        return {"tools": tool_specs} if tool_specs else {}

    async def _execute_tool(self, tool_name: str, tool_input: dict) -> str:
        """Execute a tool via MCP and return the result."""
        try:
            result = await self.session.call_tool(tool_name, tool_input)
            # Extract text content from result
            if result.content:
                for content in result.content:
                    if hasattr(content, 'text'):
                        return content.text
            return str(result)
        except Exception as e:
            return f"Error executing tool: {e}"

    async def chat(self, user_message: str) -> str:
        """Send a message and get a response, handling tool calls."""
        # Add user message
        self.messages.append({
            "role": "user",
            "content": [{"text": user_message}]
        })

        tool_config = self._format_tools_for_bedrock()

        while True:
            # Call Bedrock
            request_params = {
                "modelId": self.model_id,
                "messages": self.messages,
            }
            if tool_config:
                request_params["toolConfig"] = tool_config

            try:
                response = self.bedrock.converse(**request_params)
            except Exception as e:
                return f"Bedrock error: {e}"

            stop_reason = response.get("stopReason")
            output = response.get("output", {})
            assistant_message = output.get("message", {})

            # Add assistant response to history
            if assistant_message:
                self.messages.append(assistant_message)

            # Check if we need to execute tools
            if stop_reason == "tool_use":
                tool_results = []
                for content in assistant_message.get("content", []):
                    if content.get("toolUse"):
                        tool_use = content["toolUse"]
                        tool_name = tool_use["name"]
                        tool_input = tool_use["input"]
                        tool_use_id = tool_use["toolUseId"]

                        print(f"  [Executing tool: {tool_name}]")
                        result = await self._execute_tool(tool_name, tool_input)

                        tool_results.append({
                            "toolResult": {
                                "toolUseId": tool_use_id,
                                "content": [{"text": result}]
                            }
                        })

                # Add tool results to messages
                self.messages.append({
                    "role": "user",
                    "content": tool_results
                })
                # Continue the loop to get Claude's response to tool results
                continue

            # Extract final text response
            final_response = ""
            for content in assistant_message.get("content", []):
                if content.get("text"):
                    final_response += content["text"]

            return final_response

    def clear_history(self):
        """Clear conversation history."""
        self.messages = []


async def main():
    """Main chat loop."""
    import sys

    # Configuration
    mcp_url = "http://localhost:5001/mcp/sse"
    model_id = "anthropic.claude-sonnet-4-5-20250929-v1:0"
    region = "us-east-1"

    # Allow overrides from environment
    import os
    mcp_url = os.environ.get("MCP_URL", mcp_url)
    model_id = os.environ.get("BEDROCK_MODEL_ID", model_id)
    region = os.environ.get("AWS_REGION", region)

    agent = MCPToolboxAgent(
        mcp_url=mcp_url,
        model_id=model_id,
        region=region,
    )

    try:
        await agent.connect()
    except Exception as e:
        print(f"Failed to connect to MCP server: {e}")
        print("Make sure the MCP Toolbox server is running.")
        sys.exit(1)

    print("\nDatabase Agent Ready!")
    print("Type your questions about the database. Type 'quit' to exit, 'clear' to reset history.\n")

    try:
        while True:
            try:
                user_input = input("You: ").strip()
            except EOFError:
                break

            if not user_input:
                continue
            if user_input.lower() == "quit":
                break
            if user_input.lower() == "clear":
                agent.clear_history()
                print("Conversation history cleared.\n")
                continue

            response = await agent.chat(user_input)
            print(f"\nAssistant: {response}\n")

    finally:
        await agent.disconnect()
        print("Goodbye!")


if __name__ == "__main__":
    asyncio.run(main())
```

## Usage

### 1. Start the MCP Toolbox Server

```bash
./server/scripts/run.sh
```

### 2. Run the Agent

```bash
python agent.py
```

### 3. Chat with Your Database

```
Database Agent Ready!
Type your questions about the database. Type 'quit' to exit, 'clear' to reset history.

You: What tables are in the database?
  [Executing tool: list-tables]
Assistant: The database contains the following tables:
1. **CarReport** (schema: dbo)
2. **TransactionReport** (schema: dbo)

You: How many rows are in CarReport?
  [Executing tool: count-rows]
Assistant: The CarReport table has 1,234 rows.

You: quit
Goodbye!
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MCP_URL` | MCP Toolbox SSE endpoint | `http://localhost:5001/mcp/sse` |
| `BEDROCK_MODEL_ID` | Claude model to use | `anthropic.claude-sonnet-4-5-20250929-v1:0` |
| `AWS_REGION` | AWS region for Bedrock | `us-east-1` |

## Available Claude Models on Bedrock

| Model | Model ID | Use Case |
|-------|----------|----------|
| Claude Sonnet 4.5 | `anthropic.claude-sonnet-4-5-20250929-v1:0` | Best for coding and agents |
| Claude Opus 4.5 | `anthropic.claude-opus-4-5-20251101-v1:0` | Most intelligent |
| Claude Haiku 4.5 | `anthropic.claude-haiku-4-5-20251001-v1:0` | Fastest and cheapest |
| Claude 3.5 Sonnet | `anthropic.claude-3-5-sonnet-20240620-v1:0` | Previous generation |

## How It Works

### Tool Calling Flow

1. User sends a message
2. Agent sends message + available tools to Bedrock
3. Claude decides whether to use a tool
4. If `stopReason == "tool_use"`:
   - Agent extracts tool name and arguments
   - Executes tool via MCP
   - Sends result back to Claude
   - Repeats until Claude gives a final response
5. Agent returns Claude's text response to user

### MCP Connection

The agent uses the official MCP Python SDK to connect via SSE:

```python
from mcp import ClientSession
from mcp.client.sse import sse_client

streams = await sse_client(url="http://localhost:5001/mcp/sse")
session = ClientSession(*streams)
await session.initialize()

# List tools
tools = await session.list_tools()

# Call a tool
result = await session.call_tool("list-tables", {})
```

### Bedrock Converse API

The agent uses Bedrock's Converse API which handles tool calling natively:

```python
response = bedrock.converse(
    modelId="anthropic.claude-sonnet-4-5-20250929-v1:0",
    messages=[...],
    toolConfig={
        "tools": [
            {
                "toolSpec": {
                    "name": "list-tables",
                    "description": "List all tables",
                    "inputSchema": {"json": {...}}
                }
            }
        ]
    }
)
```

## Extending the Agent

### Add a System Prompt

```python
async def chat(self, user_message: str) -> str:
    if not self.messages:
        self.messages.append({
            "role": "user",
            "content": [{"text": "You are a helpful database assistant. Be concise."}]
        })
        # Get acknowledgment
        response = self.bedrock.converse(
            modelId=self.model_id,
            messages=self.messages,
        )
        self.messages.append(response["output"]["message"])

    # ... rest of chat method
```

### Add Streaming

```python
from botocore.eventstream import EventStream

response = self.bedrock.converse_stream(
    modelId=self.model_id,
    messages=self.messages,
    toolConfig=tool_config
)

for event in response["stream"]:
    if "contentBlockDelta" in event:
        delta = event["contentBlockDelta"]["delta"]
        if "text" in delta:
            print(delta["text"], end="", flush=True)
```

### Connect to Multiple MCP Servers

```python
class MultiMCPAgent:
    def __init__(self):
        self.sessions = {}
        self.tools = []

    async def connect(self, name: str, url: str):
        streams = await sse_client(url=url)
        session = ClientSession(*streams)
        await session.initialize()
        self.sessions[name] = session

        # Prefix tool names with server name
        tools = await session.list_tools()
        for tool in tools.tools:
            tool.name = f"{name}__{tool.name}"
            self.tools.append(tool)
```

## Troubleshooting

### Bedrock Access Denied

Ensure your AWS credentials have Bedrock permissions:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "bedrock:InvokeModel",
                "bedrock:InvokeModelWithResponseStream"
            ],
            "Resource": "*"
        }
    ]
}
```

Also ensure the model is enabled in AWS Console > Bedrock > Model Access.

### MCP Connection Failed

1. Verify the MCP server is running: `curl http://localhost:5001/`
2. Check the SSE endpoint: `curl http://localhost:5001/mcp/sse`
3. Ensure no firewall is blocking the connection

### Tool Execution Errors

Check the MCP server logs for database connection issues:

```bash
podman logs <container-id>
```

## Resources

- [Amazon Bedrock Documentation](https://docs.aws.amazon.com/bedrock/)
- [MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk)
- [Bedrock Converse API](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html)
- [Claude on Bedrock](https://docs.anthropic.com/en/docs/build-with-claude/claude-on-amazon-bedrock)
