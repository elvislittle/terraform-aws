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
    """Fetches a Terraform question using AWS Bedrock Claude."""
    if not bedrock_client:
        return "I can't get the question"
    
    try:
        response = bedrock_client.invoke_model(
            modelId='anthropic.claude-3-haiku-20240307-v1:0',
            body=json.dumps({
                "messages": [
                    {"role": "user", "content": "You are a Terraform teacher responsible for Terraform class. Provide a Terraform configuration trivia question and only the question."}
                ],
                "max_tokens": 50,
                "temperature": 0.7,
                "anthropic_version": "bedrock-2023-05-31"
            })
        )
        
        result = json.loads(response['body'].read())
        question = result['content'][0]['text'].strip()
        return question
    except Exception as e:
        print(f"Error with Bedrock: {e}")
        return "Failed to generate question. Please try again later."

def get_answer_feedback(question, answer):
    """Get feedback using AWS Bedrock Claude."""
    if not bedrock_client:
        return "I can't get feedback"
    
    try:
        prompt = f"You are a Terraform teacher responsible for Terraform class. Question: {question}\nYour Answer: {answer}\nProvide correct/incorrect feedback for completely incorrect answers only, otherwise, just say 'Correct'. Correctness is extremely important. Always err on the side of correctness."
        
        response = bedrock_client.invoke_model(
            modelId='anthropic.claude-3-haiku-20240307-v1:0',
            body=json.dumps({
                "messages": [
                    {"role": "user", "content": prompt}
                ],
                "max_tokens": 30,
                "temperature": 0.3,
                "anthropic_version": "bedrock-2023-05-31"
            })
        )
        
        result = json.loads(response['body'].read())
        feedback = result['content'][0]['text'].strip()
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
    """Test Bedrock Claude API connection."""
    if not bedrock_client:
        return jsonify({"error": "No Bedrock client"})
    
    try:
        response = bedrock_client.invoke_model(
            modelId='anthropic.claude-3-haiku-20240307-v1:0',
            body=json.dumps({
                "messages": [
                    {"role": "user", "content": "Say hello"}
                ],
                "max_tokens": 10,
                "anthropic_version": "bedrock-2023-05-31"
            })
        )
        
        result = json.loads(response['body'].read())
        return jsonify({
            "success": True,
            "response": result['content'][0]['text'].strip()
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
