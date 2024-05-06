import argparse
from flask import Flask, request, jsonify
from flask_cors import CORS 
from collections import deque

app = Flask(__name__)
CORS(app) 
# Parse command-line arguments
parser = argparse.ArgumentParser(description='Peer-to-Peer Network')
parser.add_argument('--port', type=int, default=6001, help='Port to listen on')
args = parser.parse_args()

# Transaction queue
transact_queue = deque()
transaction_queue = deque()

@app.route('/transact', methods=['POST'])
def transact():
    """Endpoint to receive new transactions."""
    data = request.get_json()
    if data:
        transact_queue.append(data)
        return jsonify({'message': 'Transaction received'}), 200
    else:
        return jsonify({'error': 'Invalid request'}), 400

@app.route('/remove_transact', methods=['POST'])
def remove_transact():
    """Endpoint to remove a transaction that has been commited"""
    data = request.get_json()
    if data:
        try:
            transact_queue.remove(data)
        except ValueError:
            return jsonify({'error': 'Transaction not found'}), 404
        return jsonify({'message': 'Transaction removed'}), 200
    else:
        return jsonify({'error': 'Invalid request'}), 400

@app.route('/process_transact', methods=['GET'])
def process_transact():
    """Endpoint to retrieve transactions from the transact_queue."""
    if transact_queue:
        transactions = list(transact_queue)
        return jsonify(transactions), 200
    else:
        return jsonify([]), 200

@app.route('/transaction', methods=['GET', 'POST'])
def get_transactions():
    if request.method == 'POST':
        data = request.get_json()
        if data:
            transaction_queue.append(data)
            return jsonify({'message': 'Transaction received'}), 200
        else:
            return jsonify({'error': 'Invalid request'}), 400
    elif request.method == 'GET':
        """Endpoint to retrieve transactions."""
        transactions = list(transaction_queue)
        return jsonify(transactions), 200

if __name__ == '__main__':
    app.run(host='localhost', port=args.port)