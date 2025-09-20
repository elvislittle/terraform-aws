from flask import Flask, request, jsonify, Blueprint
from flask_cors import CORS
import boto3
import json
import os

app = Flask(__name__)
CORS(app, resources={"/api/*": {"origins": "*"}})

# Initialize Bedrock client
try:
    bedrock_client = boto3.client('bedrock-runtime', region_name='us-east-1')
except Exception as e:
    bedrock_client = None
    print(f"Warning: Could not initialize Bedrock client: {e}")

def get_terraform_question():
    """Fetches a Terraform question using AWS Bedrock."""
    if not bedrock_client:
        return "I can't get the question"
    
    try:
        response = bedrock_client.invoke_model(
            modelId='amazon.titan-text-express-v1',
            body=json.dumps({
                "inputText": "You are a Terraform teacher responsible for Terraform class. Provide a Terraform configuration trivia question and only the question.",
                "textGenerationConfig": {
                    "maxTokenCount": 50,
                    "temperature": 0.7,
                    "stopSequences": ["\n", "?"]
                }
            })
        )
        
        result = json.loads(response['body'].read())
        question = result['results'][0]['outputText'].strip()
        
        # Clean up the response - remove any extra text after the question
        if '?' in question:
            question = question.split('?')[0] + '?'
        
        return question
    except Exception as e:
        print(f"Error with Bedrock: {e}")
        return "Failed to generate question. Please try again later."

def get_answer_feedback(question, answer):
    """Get feedback using AWS Bedrock."""
    if not bedrock_client:
        return "I can't get feedback"
    
    try:
        prompt = f"You are a Terraform teacher. Question: {question}\nStudent Answer: {answer}\nProvide correct/incorrect feedback for completely incorrect answers only, otherwise, just say 'Correct'. Correctness is extremely important. Always err on the side of correctness."
        
        response = bedrock_client.invoke_model(
            modelId='amazon.titan-text-express-v1',
            body=json.dumps({
                "inputText": prompt,
                "textGenerationConfig": {
                    "maxTokenCount": 30,
                    "temperature": 0.3,
                    "stopSequences": ["\n"]
                }
            })
        )
        
        result = json.loads(response['body'].read())
        feedback = result['results'][0]['outputText'].strip()
        return feedback
    except Exception as e:
        print(f"Error with Bedrock feedback: {e}")
        return "Failed to get feedback. Please try again later."

# Create a Blueprint for API routes with the prefix /api
api_bp = Blueprint('api', __name__, url_prefix='/api')

@api_bp.route('/healthcheck', methods=['GET'])
def healthcheck():
    """Simple healthcheck endpoint to verify that the service is running."""
    return jsonify({"status": "ok"})

@api_bp.route('/test-bedrock', methods=['GET'])
def test_bedrock():
    """Test Bedrock API connection."""
    if not bedrock_client:
        return jsonify({"error": "No Bedrock client"})
    
    try:
        response = bedrock_client.invoke_model(
            modelId='amazon.titan-text-express-v1',
            body=json.dumps({
                "inputText": "Say hello",
                "textGenerationConfig": {
                    "maxTokenCount": 5,
                    "temperature": 0.7
                }
            })
        )
        
        result = json.loads(response['body'].read())
        return jsonify({
            "success": True,
            "response": result['results'][0]['outputText'].strip()
        })
    except Exception as e:
        return jsonify({
            "success": False,
            "error": str(e),
            "error_type": str(type(e))
        })

@api_bp.route('/question', methods=['GET'])
def question_endpoint():
    """API endpoint to get a Terraform question."""
    question_text = get_terraform_question()
    return jsonify({"question": question_text})

@api_bp.route('/submit', methods=['POST'])
def submit():
    """API endpoint to submit an answer and get feedback."""
    data = request.get_json()
    question_text = data.get('question')
    user_answer = data.get('answer')
    if not question_text or not user_answer:
        return jsonify({"error": "Question and answer are required."}), 400
    feedback_text = get_answer_feedback(question_text, user_answer)
    return jsonify({"feedback": feedback_text})

# Register the Blueprint with the Flask application
app.register_blueprint(api_bp)

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)