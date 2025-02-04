class SignUpWithEmailAndPasswordFailure {
  final String message;

  const SignUpWithEmailAndPasswordFailure([this.message = "An Unknown error occured."]);


  factory SignUpWithEmailAndPasswordFailure.code(String code){
    switch(code){
      case'weak-password' :
        return SignUpWithEmailAndPasswordFailure('Please enter stronger password');
      case'invalid-email' :
        return SignUpWithEmailAndPasswordFailure('Email is not valid or Badly formatted');
      case'email-already-in-use' :
        return SignUpWithEmailAndPasswordFailure('An account already exists');
      case'operation-not-allowed' :
        return SignUpWithEmailAndPasswordFailure('Operation is not allowed');
      case'user-disabled' :
        return SignUpWithEmailAndPasswordFailure('This user has been disabled');

    default:
      return SignUpWithEmailAndPasswordFailure();




    }
  }
}