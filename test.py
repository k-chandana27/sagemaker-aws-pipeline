# test_endpoint.py
import boto3
import json

def test_endpoint():
    # Create a session using your profile
    session = boto3.Session(profile_name='edii-ai-bot-1')

    # Create the SageMaker runtime client using the session
    runtime_client = session.client("sagemaker-runtime")
    endpoint_name = "logs-error-endpoint-20250503200924"

    # Test cases
    test_errors = [
      "Order : 12312 Error given by UPI "
    ]

    try:
        for error in test_errors:
            # Send the error message as a list
            response = runtime_client.invoke_endpoint(
                EndpointName=endpoint_name,
                ContentType='application/json',
                Accept='application/json',
                Body=json.dumps([error])
            )
            
            result = json.loads(response['Body'].read().decode())
            print(f"\nInput Error: {error}")
            print(f"Predicted Action: {result[0]}")
            
    except Exception as e:
        print(f"Error invoking endpoint: {str(e)}")
        if hasattr(e, 'response'):
            print(f"Error response: {e.response}")

if __name__ == "__main__":
    test_endpoint()