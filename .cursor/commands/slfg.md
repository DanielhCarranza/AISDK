<!-- Full autonomous engineering workflow using swarm mode for parallel execution -->

## Arguments
[feature description]

Swarm-enabled LFG. Run these steps in order, parallelizing where indicated.

## Sequential Phase

1. `/ralph-loop "finish all slash commands" --completion-promise "DONE"`
2. `/plan $ARGUMENTS`
3. `/deepen-plan`
4. `/work` — **Use swarm mode**: Make a Task list and launch an army of agent swarm subagents to build the plan

## Parallel Phase

After work completes, launch steps 5 and 6 as **parallel swarm agents** (both only need code to be written):

5. `/review` — spawn as background Task agent
6. `/test-browser` — spawn as background Task agent

Wait for both to complete before continuing.

## Finalize Phase

7. `/resolve_todo_parallel` — resolve any findings from the review
8. `/feature-video` — record the final walkthrough and add to PR
9. Output `<promise>DONE</promise>` when video is in PR

Start with step 1 now.
