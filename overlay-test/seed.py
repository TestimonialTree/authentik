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
from authentik.providers.proxy.models import ProxyMode, ProxyProvider

REDIRECT_URI = "https://api.rechat.com/testimonialtree/auth/done"
PROXY_EXTERNAL_HOST = "https://staff.example.com"

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

# Forward-auth proxy provider, set up the way the API serializer does it: Authentik
# derives the callback URLs from external_host (regex-escaped on 2024.8.3).
proxy = ProxyProvider.objects.filter(name="overlay-test-proxy").first()
if not proxy:
    proxy = ProxyProvider(
        name="overlay-test-proxy",
        authorization_flow=flow,
        client_id="overlay-test-proxy",
        client_secret="pr0xy",
    )
proxy.mode = ProxyMode.FORWARD_SINGLE
proxy.external_host = PROXY_EXTERNAL_HOST
proxy.save()
proxy.set_oauth_defaults()
proxy.save()
Application.objects.get_or_create(slug="overlay-test-proxy", defaults=dict(name="overlay-test-proxy", provider=proxy))

scopes = {
    "code-plain": (provider, ["openid"]),
    "code-wrong-redirect": (provider, ["openid"]),
    "code-wrong-secret": (provider, ["openid"]),
    "code-offline": (provider, ["openid", "offline_access"]),
    "code-cors": (provider, ["openid"]),
    "code-proxy": (proxy, ["openid", "email", "ak_proxy"]),
    "code-proxy-escaped": (proxy, ["openid"]),
    "code-proxy-wrong-redirect": (proxy, ["openid"]),
}
for code, (code_provider, scope) in scopes.items():
    AuthorizationCode.objects.filter(code=code).delete()
    AuthorizationCode.objects.create(
        provider=code_provider,
        user=user,
        code=code,
        expires=timezone.now() + timedelta(minutes=30),
        scope=scope,
        auth_time=timezone.now(),
    )
print("seeded")
