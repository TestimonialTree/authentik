"""Seed fixtures for overlay-test/run.sh. Runs inside the server container via `ak shell`.

Works on the 2024.8.3 base (redirect_uris is a string) and on newer bases
(redirect_uris is a list of RedirectURI objects).
"""

from datetime import timedelta

from django.utils import timezone

from authentik.core.models import Application, User
from authentik.flows.models import Flow, FlowDesignation
from authentik.providers.oauth2 import models as oauth2_models
from authentik.providers.oauth2.models import AuthorizationCode, OAuth2Provider

REDIRECT_URI = "https://api.rechat.com/testimonialtree/auth/done"

flow, _ = Flow.objects.get_or_create(
    slug="overlay-test-authz",
    defaults=dict(name="overlay-test", title="overlay-test", designation=FlowDesignation.AUTHORIZATION),
)
user, _ = User.objects.get_or_create(username="overlay-agent", defaults=dict(email="agent@example.com"))
user.set_password("AgentPw!2478")
user.save()

provider = OAuth2Provider.objects.filter(name="overlay-test").first()
if not provider:
    provider = OAuth2Provider(
        name="overlay-test",
        authorization_flow=flow,
        client_id="overlay-test",
        client_secret="s3cret",
    )
if hasattr(oauth2_models, "RedirectURI"):
    provider.redirect_uris = [
        oauth2_models.RedirectURI(oauth2_models.RedirectURIMatchingMode.STRICT, REDIRECT_URI)
    ]
else:
    provider.redirect_uris = REDIRECT_URI
provider.save()
Application.objects.get_or_create(slug="overlay-test", defaults=dict(name="overlay-test", provider=provider))

scopes = {
    "code-plain": ["openid"],
    "code-wrong-redirect": ["openid"],
    "code-wrong-secret": ["openid"],
    "code-offline": ["openid", "offline_access"],
    "code-cors": ["openid"],
}
for code, scope in scopes.items():
    AuthorizationCode.objects.filter(code=code).delete()
    AuthorizationCode.objects.create(
        provider=provider,
        user=user,
        code=code,
        expires=timezone.now() + timedelta(minutes=30),
        scope=scope,
        auth_time=timezone.now(),
    )
print("seeded")
