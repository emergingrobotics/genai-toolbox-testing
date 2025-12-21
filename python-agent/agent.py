#!/usr/bin/env python3
"""
Python agent that connects Amazon Bedrock (Claude) to MCP Toolbox.
Provides a chat interface with database tool access.
"""

import asyncio
import os
import sys
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
    # Configuration with environment variable overrides
    mcp_url = os.environ.get("MCP_URL", "http://localhost:5001/mcp/sse")
    model_id = os.environ.get("BEDROCK_MODEL_ID", "anthropic.claude-sonnet-4-5-20250929-v1:0")
    region = os.environ.get("AWS_REGION", "us-east-1")

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
