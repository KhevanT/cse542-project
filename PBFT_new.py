import asyncio
import websockets
import argparse
import json
import random
import requests
from collections import defaultdict

# Parse command-line arguments
parser = argparse.ArgumentParser(description='Peer-to-Peer Network')
parser.add_argument('--port', type=int, default=8000, help='Port to listen on')
parser.add_argument('--http_port', type=int, default=6000, help='HTTP Port to listen on')
parser.add_argument('peers', nargs='*', help='Addresses of peers to connect to')
args = parser.parse_args()

# Transaction pool
transaction_pool = []

# List of connected peers
connected_peers = []

# Peer status
peer_status = "online"

# Constants
MAX_NODES = 2
MAX_FAULTY_NODES = (MAX_NODES - 1) // 3

# State variables
sequence_number = 0
prepared = defaultdict(lambda: list())
committed = defaultdict(lambda: list())

# View and primary
current_view = 0
view_change_threshold = 2
if len(connected_peers) > 0:
    primary = connected_peers[current_view % len(connected_peers)]
else:
    primary = None

async def broadcast_message(message):
    """Broadcast a message to all connected peers."""
    for peer in connected_peers:
        try:
            await peer.send(json.dumps(message))
        except Exception as e:
            print(f"Error broadcasting message: {e}")

async def pre_prepare(transaction):
    """Broadcast a pre-prepare message with the transaction."""
    global sequence_number, primary, current_view

    # if primary is None or connected_peers != 0:
    #     if len(connected_peers) <= 0:
    #         print("No primary node available, cannot pre-prepare transaction.")
    #     else:
    #         primary = connected_peers[current_view % len(connected_peers)]
    #     return

    message = {
        'type': 'pre-prepare',
        'view': current_view,
        'sequence_number': sequence_number,
        'transaction': transaction,
    }
    await broadcast_message(message)

async def prepare(message):
    """Handle a pre-prepare message and broadcast a prepare message."""
    global sequence_number, prepared, current_view
    if (
        message['view'] == current_view and
        message['sequence_number'] == sequence_number
    ):
        print(message, prepared)
        prepared[message['sequence_number']].append(message['transaction'])
        
        if len(prepared[message['sequence_number']]) >= 2 * MAX_FAULTY_NODES + 1:
            print(f"Pre-prepare {message['sequence_number']} is prepared.")
            prepare_message = {
                'type': 'prepare',
                'view': current_view,
                'sequence_number': sequence_number,
                'transaction': message['transaction'],
            }
            await broadcast_message(prepare_message)

async def commit(message):
    """Handle a prepare message and broadcast a commit message."""
    global sequence_number, committed, current_view
    if (
        message['view'] == current_view and
        message['sequence_number'] == sequence_number and
        message['transaction'] in prepared[message['sequence_number']]
    ):
        committed[message['sequence_number']].append(message['transaction'])
        if len(committed[message['sequence_number']]) >= 2 * MAX_FAULTY_NODES + 1:
            print(f"Prepare {message['sequence_number']} is committed.")
            commit_message = {
                'type': 'commit',
                'view': current_view,
                'sequence_number': sequence_number,
                'transaction': message['transaction'],
            }
            await broadcast_message(commit_message)

async def finalize_transaction(message):
    """Finalize the transaction if enough commit messages are received."""
    global sequence_number, committed, current_view
    if (
        message['view'] == current_view and
        message['sequence_number'] == sequence_number and
        len(committed[message['sequence_number']]) >= 2 * MAX_FAULTY_NODES + 1
    ):
        transaction = list(committed[message['sequence_number']])[0]
        # Finalize the transaction (add to transaction log, update state)
        print(f"Finalizing transaction: {transaction}")
        sequence_number += 1

        requests.post(f'http://localhost:{args.http_port}/transaction', json=transaction)
        requests.post(f'http://localhost:{args.http_port}/remove_transact', json=transaction)

        # if len(committed) % view_change_threshold == 0:
        #     await view_change(message)

# async def view_change(message):
#     """Initiate a view change if enough view-change messages are received."""
#     global current_view, primary
#     if (
#         message['view'] > current_view and
#         len(message['view_changes']) >= 2 * MAX_FAULTY_NODES + 1
#     ):
#         current_view = message['view']
#         primary = connected_peers[current_view % len(connected_peers)]
#         print(f"Changing view to {current_view}, new primary is {primary}")

#         # Reset state variables
#         sequence_number = 0
#         prepared.clear()
#         committed.clear()

#         # Broadcast new view message
#         new_view_message = {
#             'type': 'new-view',
#             'view': current_view,
#             'primary': primary
#         }
#         await broadcast_message(new_view_message)

async def handle_message(websocket, path):
    """Handle incoming messages from connected peers."""
    async for message in websocket:
        message = json.loads(message)
        if message['type'] == 'transaction':
            # if (websocket.remote_address == primary):
            await pre_prepare(message['data'])
            print(f"Received transaction: {message['data']}")
        elif message['type'] == 'status':
            print(f"Received status from peer: {message['data']}")
        elif message['type'] == 'peer':
            peer_address = message['data']
            if peer_address not in connected_peers:
                try:
                    peer = await websockets.connect(peer_address)
                    connected_peers.append(peer)
                    print(f"Connected to peer: {peer_address}")
                except Exception as e:
                    print(f"Error connecting to peer: {e}")
        elif message['type'] == 'pre-prepare':
            await prepare(message)
        elif message['type'] == 'prepare':
            await commit(message)
        elif message['type'] == 'commit':
            await finalize_transaction(message)
        # elif message['type'] == 'view-change':
        #     await view_change(message)

async def process_transactions():
    """Fetch transactions from the /process_transact endpoint and broadcast pre-prepare messages."""
    while True:
        try:
            response = requests.get(f'http://localhost:{args.http_port}/process_transact')
            transactions = response.json()
            for transaction in transactions:
                print(f"Processing transaction: {transaction}")
                # if connected_peers.index(websocket.remote_addr) == primary:
                await broadcast_message({
                    'type': 'transaction',
                    'data': transaction
                })

                await pre_prepare(transaction)
                # else:
                #     print(f"Forwarding transaction: {transaction} to primary")
                #     await broadcast_message({
                #         'type': 'transaction',
                #         'data': transaction
                #     })
        except Exception as e:
            print(f"Error fetching transactions from /process_transact: {e}")
        await asyncio.sleep(5)  # Poll for new transactions every 5 seconds

async def start_server():
    """Start the websocket server and connect to initial peers."""
    async with websockets.serve(handle_message, "localhost", args.port):
        print(f"Server started on port {args.port}")

        # Connect to initial peers
        for peer_address in args.peers:
            try:
                peer = await websockets.connect(peer_address)
                connected_peers.append(peer)
                print(f"Connected to peer: {peer_address}")
                # Notify the peer about our existence
                await peer.send(json.dumps({'type': 'peer', 'data': f"ws://localhost:{args.port}"}))
            except Exception as e:
                print(f"Error connecting to peer: {e}")

        # Broadcast our status to connected peers
        await broadcast_message({'type': 'status', 'data': peer_status})

        # Start processing transactions from the Flask server
        asyncio.create_task(process_transactions())

        # Wait forever (until interrupted)
        await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(start_server())